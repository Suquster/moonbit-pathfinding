// hybrid.mbt —— 容量受限的惰性 DFA / NFA 混合匹配器 `HybridMatcher`。
//
// 对应 design.md §「Regex 引擎增强设计 / 5.3 Hybrid 匹配」（Requirement 5.3/5.4）。
// 本文件为**新增**（bypass），不修改任何既有签名。
//
// 设计动机（paper-to-code：RE2 的 lazy DFA + NFA 回退思想）：
//   惰性 DFA 在匹配过程中按需把"NFA 状态核 + 锚点标志 + 字符"映射到后继核，
//   并缓存转移结果，从而把重复出现的状态转移摊还为 O(1) 查表（DFA 路径）。
//   但在病态正则下，可达 DFA 状态数可能爆炸；生产级实现必须对缓存设上限。
//   当缓存达到容量上限、无法再为新状态分配稳定身份时，混合匹配器**切换**到
//   直接的 NFA/Pike 风格模拟（在当前 NFA 状态核上按 `closure`/`move_on`
//   逐步推进，不再新增缓存项），从而以"空间换确定性"——既限制内存占用，又
//   保证总能完成匹配（AC4）。
//
// 为何结果恒等于 `Nfa::find`（核心不变量，5.4 属性测试守护）：
//   无论走 DFA 缓存路径还是 NFA 回退路径，每一步的"接受判定"与"字符转移"
//   都由完全相同的 `Nfa::closure` / `Nfa::move_on` / `list_contains` 计算得出。
//   缓存仅以稳定状态 id 为键**记忆**这些确定性计算的结果，从不改变其取值；
//   回退路径则直接在状态核上重算同样的结果。因此对任意输入与任意 `cap`，
//   `HybridMatcher::find` 与 `Dfa::find` / `Nfa::find` 给出逐字符一致的匹配
//   区间（最左最长语义）。

///|
/// 缓存未命中 / 无法分配稳定状态身份的哨兵 id（触发 NFA 回退路径）。
const HYBRID_NO_STATE : Int = -1

///|
/// 转移记忆表中表示"死路（无字符转移）"的哨兵值，与合法状态 id（≥0）区分。
const HYBRID_DEAD : Int = -2

///|
/// 将锚点标志（0..3）折叠进转移键时使用的步长：保证 `flags * stride + code`
/// 在 `flags ∈ 0..3`、`code ∈ 0..MAX_CODE` 下唯一。
const HYBRID_FLAG_STRIDE : Int = MAX_CODE + 2

///|
/// 混合匹配器：持有源 NFA 与惰性 DFA 状态缓存容量上限。
///
///   * `nfa`       —— 源 NFA（复用既有 Thompson 构造产物）；
///   * `cache_cap` —— 惰性 DFA 状态缓存可容纳的不同状态核数上限；达到上限后
///     当前转移退回 NFA 模拟（不再新增缓存项）。`cap <= 0` 等价于纯 NFA 路径。
pub struct HybridMatcher {
  nfa : Nfa
  cache_cap : Int
}

///|
/// 由 NFA 与缓存容量上限构造混合匹配器。
pub fn HybridMatcher::new(nfa : Nfa, cap~ : Int) -> HybridMatcher {
  { nfa, cache_cap: cap }
}

///|
/// 单次匹配期间的惰性 DFA 缓存（跨所有起点复用）。
///
///   * `core_id`     —— NFA 状态核编码 → 稳定状态 id；
///   * `cores`       —— 状态 id → 状态核（排序去重整型列表）；
///   * `accept_memo` —— `"id|flags"` → 该状态在给定锚点标志下是否接受；
///   * `trans_memo`  —— `"id|combo"` → 后继状态 id（或 `HYBRID_DEAD` 死路）。
priv struct HybridCache {
  core_id : Map[String, Int]
  cores : Array[Array[Int]]
  accept_memo : Map[String, Bool]
  trans_memo : Map[String, Int]
}

///|
/// 新建空缓存。
fn HybridCache::new() -> HybridCache {
  { core_id: Map([]), cores: [], accept_memo: Map([]), trans_memo: Map([]) }
}

///|
/// 物化（intern）一个状态核：命中缓存则复用 id；未命中且容量未满则分配新
/// id 并缓存；**容量已满**则返回 `HYBRID_NO_STATE`，由调用方切换到 NFA 回退。
fn HybridMatcher::intern(
  self : HybridMatcher,
  cache : HybridCache,
  core : Array[Int],
) -> Int {
  let key = encode_core(core)
  match cache.core_id.get(key) {
    Some(id) => id
    None =>
      if cache.cores.length() >= self.cache_cap {
        HYBRID_NO_STATE
      } else {
        let id = cache.cores.length()
        cache.core_id[key] = id
        cache.cores.push(core)
        id
      }
  }
}

///|
/// 由锚点标志（0..3）还原"是否串首"。
fn hybrid_flag_start(flags : Int) -> Bool {
  flags == 1 || flags == 3
}

///|
/// 由锚点标志（0..3）还原"是否串尾"。
fn hybrid_flag_end(flags : Int) -> Bool {
  flags == 2 || flags == 3
}

///|
/// 判定给定状态（核 `core`，可选稳定 id `sid`）在锚点标志 `flags` 下是否接受。
/// DFA 路径（`sid >= 0`）查/存 `accept_memo`；NFA 回退路径直接在核上计算。
fn HybridMatcher::is_accepting(
  self : HybridMatcher,
  cache : HybridCache,
  sid : Int,
  core : Array[Int],
  flags : Int,
) -> Bool {
  if sid >= 0 {
    let key = sid.to_string() + "|" + flags.to_string()
    match cache.accept_memo.get(key) {
      Some(b) => b
      None => {
        let active = self.nfa.closure(
          core,
          hybrid_flag_start(flags),
          hybrid_flag_end(flags),
        )
        let b = list_contains(active, self.nfa.accept)
        cache.accept_memo[key] = b
        b
      }
    }
  } else {
    let active = self.nfa.closure(
      core,
      hybrid_flag_start(flags),
      hybrid_flag_end(flags),
    )
    list_contains(active, self.nfa.accept)
  }
}

///|
/// 计算从当前状态（核 `core`，可选稳定 id `sid`）在锚点标志 `flags` 下消费
/// 码点 `code` 的后继。返回 `Some((后继 id, 后继核))`；无字符转移返回 `None`。
///
/// DFA 路径（`sid >= 0` 且命中 `trans_memo`）直接查表复用；否则用 NFA 计算
/// 该步并在双方均有稳定 id 时记忆。后继核无法分配稳定 id（容量已满）时，
/// 后继 id 为 `HYBRID_NO_STATE`，调用方据此进入 NFA 回退路径。
fn HybridMatcher::step(
  self : HybridMatcher,
  cache : HybridCache,
  sid : Int,
  core : Array[Int],
  flags : Int,
  code : Int,
) -> (Int, Array[Int])? {
  let combo = flags * HYBRID_FLAG_STRIDE + code
  let key = sid.to_string() + "|" + combo.to_string()
  // DFA 缓存命中：直接复用已记忆的转移结果。
  if sid >= 0 {
    match cache.trans_memo.get(key) {
      Some(t) =>
        if t == HYBRID_DEAD {
          return None
        } else {
          return Some((t, cache.cores[t]))
        }
      None => ()
    }
  }
  // 缓存未命中（或处于回退态）：用 NFA 计算该步。
  let active = self.nfa.closure(
    core,
    hybrid_flag_start(flags),
    hybrid_flag_end(flags),
  )
  let moved = self.nfa.move_on(active, code)
  if moved.length() == 0 {
    if sid >= 0 {
      cache.trans_memo[key] = HYBRID_DEAD
    }
    return None
  }
  let next_core = self.nfa.closure(moved, false, false)
  next_core.sort()
  let nsid = self.intern(cache, next_core)
  // 仅当源与目标都有稳定 id 时，记忆该转移以供后续 O(1) 复用。
  if sid >= 0 && nsid >= 0 {
    cache.trans_memo[key] = nsid
  }
  Some((nsid, next_core))
}

///|
/// 自固定起点 `start` 在混合匹配器上模拟，返回最长接受位置（开区间端点）；
/// 无接受位置可达时返回 `None`。容量充足时走惰性 DFA 缓存路径，容量耗尽时
/// 自动切换到 NFA 模拟路径，二者结果一致。
fn HybridMatcher::match_at(
  self : HybridMatcher,
  cache : HybridCache,
  chars : Array[Char],
  n : Int,
  start : Int,
) -> Int? {
  let start_core = self.nfa.closure([self.nfa.start], false, false)
  start_core.sort()
  // sid：当前状态稳定 id；HYBRID_NO_STATE 表示已切换到 NFA 回退路径。
  let mut sid = self.intern(cache, start_core)
  // core：当前状态核，无论是否缓存命中都维护，保证回退路径可用。
  let mut core = start_core
  let mut pos = start
  let mut best : Int? = None
  while true {
    let flags = flag_index(pos == 0, pos == n)
    if self.is_accepting(cache, sid, core, flags) {
      best = Some(pos)
    }
    if pos >= n {
      break
    }
    match self.step(cache, sid, core, flags, chars[pos].to_int()) {
      None => break
      Some((nsid, ncore)) => {
        sid = nsid
        core = ncore
        pos = pos + 1
      }
    }
  }
  best
}

///|
/// 基于混合匹配器的最左最长匹配（语义与 `Nfa::find` / `Dfa::find` 一致）：
/// 自最小起始偏移起逐一尝试，返回首个能匹配的起点及其最长匹配区间；无匹配
/// 返回 `None`。单次匹配内复用同一惰性 DFA 缓存（跨起点共享）。
pub fn HybridMatcher::find(self : HybridMatcher, input : String) -> Match? {
  let chars = input.iter().to_array()
  let n = chars.length()
  let cache = HybridCache::new()
  for i in 0..<=n {
    match self.match_at(cache, chars, n, i) {
      Some(endp) => return Some({ start: i, end: endp })
      None => ()
    }
  }
  None
}
