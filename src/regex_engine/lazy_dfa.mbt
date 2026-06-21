// lazy_dfa.mbt —— 惰性 DFA `LazyDfa`（on-the-fly 子集构造，旗舰深化）。
//
// 对应 design.md §4.9（R7.3/7.4）。本文件为**新增**。惰性 DFA 在匹配过程中
// 按需增量计算并缓存所需 DFA 状态（NFA 状态核），而非预先物化整张转移表
// （对照 `to_dfa` 的完整子集构造）。
//
// paper-to-code：on-the-fly subset construction（RE2 的惰性 DFA 思想）。本实现
// 复用既有 `Nfa::closure` / `Nfa::move_on` / `encode_core`，DFA 状态 = NFA 状态
// 核（无条件 ε 闭包后的排序去重整型列表）；执行时按需对遇到的 `(状态, 锚点
// 标志, 字符)` 计算后继核并缓存（跨所有起点复用），与完整 `to_dfa` 对同一
// `(正则, 输入)` 给出一致的整体匹配区间（R7.4，P2）。

///|
/// 惰性 DFA：持有源 NFA 与已物化状态缓存。
///
///   * `nfa`   —— 源 NFA；
///   * `cache` —— 已物化 DFA 状态（NFA 核编码 → 状态 id）；
///   * `cores` —— 状态 id → NFA 状态核（排序去重整型列表）。
pub struct LazyDfa {
  nfa : Nfa
  cache : Map[String, Int]
  cores : Array[Array[Int]]
}

///|
/// 惰性 DFA 已物化状态数的默认上界（缓存淘汰预算）。
///
/// 命名常量（规避 magic number）。惰性 DFA 在匹配过程中按需物化 DFA 状态
/// （NFA 核），对病态正则其状态数可指数膨胀。RE2 的做法是在缓存触及内存预算
/// 时**整体刷新** DFA 缓存并按需重建，从而保持内存有界而不牺牲正确性。本常量
/// 即默认状态预算；逾界即刷新（见 `match_at_limited`）。
let default_lazy_dfa_budget : Int = 10000

///|
/// 当已物化状态数达到 `budget` 时，整体清空状态缓存（cache + cores），使后续
/// 状态按需重建，从而将惰性 DFA 的内存占用约束在 O(budget)。清空是
/// **安全**的：DFA 状态由 NFA 核确定性地复算得到，刷新仅影响内存，不改变任何
/// 匹配结果（缓存淘汰，R7.3）。返回是否发生了刷新。
fn LazyDfa::maybe_evict(self : LazyDfa, budget : Int) -> Bool {
  if self.cores.length() >= budget {
    self.cache.clear()
    self.cores.clear()
    true
  } else {
    false
  }
}

///|
/// 由 NFA 构造惰性 DFA（尚未物化任何状态）。
pub fn LazyDfa::new(nfa : Nfa) -> LazyDfa {
  { nfa, cache: Map([]), cores: [] }
}

///|
/// 物化（intern）一个 NFA 核：命中缓存则复用其 id，否则分配新 id 并缓存。
fn LazyDfa::intern(self : LazyDfa, core : Array[Int]) -> Int {
  let key = encode_core(core)
  match self.cache.get(key) {
    Some(id) => id
    None => {
      let id = self.cores.length()
      self.cache[key] = id
      self.cores.push(core)
      id
    }
  }
}

///|
/// 基于惰性 DFA 的最左最长匹配（语义与 `Dfa::find` 一致）：自最小起始偏移起
/// 逐一尝试，返回首个能匹配的起点及其最长匹配区间；无匹配返回 `None`。
///
/// 使用默认状态预算 `default_lazy_dfa_budget` 进行缓存淘汰，保持内存有界。
pub fn LazyDfa::find(self : LazyDfa, input : String) -> Match? {
  self.find_with_limit(input, default_lazy_dfa_budget)
}

///|
/// 与 `find` 语义一致，但显式指定惰性 DFA 状态缓存的淘汰预算 `max_states`
/// （旗舰深化旁路新增）：已物化状态数达到该预算时整体刷新缓存并按需重建，
/// 将内存占用约束在 O(max_states)。`max_states < 1` 时按 1 处理（每步刷新，
/// 退化为零缓存仍正确）。匹配结果与不淘汰时**逐位相等**（缓存淘汰仅影响内存，
/// 不影响语义，R7.3/7.4）。
pub fn LazyDfa::find_with_limit(
  self : LazyDfa,
  input : String,
  max_states : Int,
) -> Match? {
  let budget = if max_states < 1 { 1 } else { max_states }
  let chars = input.iter().to_array()
  let n = chars.length()
  for i in 0..<=n {
    match self.match_at_limited(chars, n, i, budget) {
      Some(endp) => return Some({ start: i, end: endp })
      None => ()
    }
  }
  None
}

///|
/// 自固定起点 `start` 在惰性 DFA 上模拟，返回最长接受位置（开区间端点）；
/// 无接受位置可达时返回 `None`。按需计算后继核并缓存，并在已物化状态数达到
/// `budget` 时整体刷新缓存（缓存淘汰，保持内存有界）。
///
/// 刷新安全性：每次刷新发生在「计算出 `next_core` 之后、intern 之前」，故刷新
/// 后立即 intern 当前 `next_core` 取得有效 id，循环顶部对 `cores[state]` 的读取
/// 始终指向一个有效（刚 intern 的）核；`best` 为局部值不受缓存刷新影响。
fn LazyDfa::match_at_limited(
  self : LazyDfa,
  chars : Array[Char],
  n : Int,
  start : Int,
  budget : Int,
) -> Int? {
  let start_core = self.nfa.closure([self.nfa.start], false, false)
  start_core.sort()
  let mut state = self.intern(start_core)
  let mut pos = start
  let mut best : Int? = None
  while true {
    let core = self.cores[state]
    let active = self.nfa.closure(core, pos == 0, pos == n)
    if list_contains(active, self.nfa.accept) {
      best = Some(pos)
    }
    if pos >= n {
      break
    }
    let moved = self.nfa.move_on(active, chars[pos].to_int())
    if moved.length() == 0 {
      break
    }
    let next_core = self.nfa.closure(moved, false, false)
    next_core.sort()
    // 缓存淘汰：物化状态数达预算则整体刷新，随后 intern 当前后继核重建。
    let _ = self.maybe_evict(budget)
    state = self.intern(next_core)
    pos = pos + 1
  }
  best
}
