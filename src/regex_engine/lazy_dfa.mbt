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
pub fn LazyDfa::find(self : LazyDfa, input : String) -> Match? {
  let chars = input.iter().to_array()
  let n = chars.length()
  for i in 0..<=n {
    match self.match_at(chars, n, i) {
      Some(endp) => return Some({ start: i, end: endp })
      None => ()
    }
  }
  None
}

///|
/// 自固定起点 `start` 在惰性 DFA 上模拟，返回最长接受位置（开区间端点）；
/// 无接受位置可达时返回 `None`。按需计算后继核并缓存。
fn LazyDfa::match_at(
  self : LazyDfa,
  chars : Array[Char],
  n : Int,
  start : Int,
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
    state = self.intern(next_core)
    pos = pos + 1
  }
  best
}
