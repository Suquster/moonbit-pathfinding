// bounded_backtrack.mbt —— 有界回溯引擎 `BoundedBacktracker`（旗舰深化）。
//
// paper-to-code：Rust regex-automata `nfa/thompson/backtrack.rs` 的
// BoundedBacktracker：经典回溯搜索 + 「(pc, pos) 已访问位图」记忆化——
// 每个 (指令, 输入位置) 状态至多探索一次，故总步数硬上界为
// O(|program| × (|input|+1))，**绝不指数回溯**；位图容量即内存预算，
// 超预算显式报告（BtOverBudget）而非退化，调用侧可回退 Pike VM
// （`exec_bounded` 即该 meta-engine 策略）。
//
// 语义不变量（差分 PBT 守护）：DFS 按 `ISplit(a, b)` 先 a 后 b 的优先级
// 探索，首达 `IMatch` 即返回——与 Pike VM `LeftmostFirst` 的「线程入列
// 顺序即优先级、首达即结果」逐字符一致（含捕获寄存器取值）。
// (pc, pos) 去重不改变该语义：匹配可达性只取决于 (pc, pos)，与捕获
// 寄存器取值无关，故失败状态的剪枝不会剪掉任何本可成功的高优先级路径。

///|
/// 有界回溯的默认状态预算（已访问位图的最大位数）。
///
/// 与 Rust regex-automata 同数量级（其 `DEFAULT_VISITED_CAPACITY` 为
/// 256 KiB 位图）。预算内可处理 |program| × (|input|+1) ≤ 该值的搜索。
pub const BOUNDED_BACKTRACK_BUDGET : Int = 2097152

///|
/// 有界回溯结果：命中 / 未命中 / 超出状态预算（需回退其他引擎）。
pub(all) enum BacktrackResult {
  BtMatch(Captures)
  BtNoMatch
  BtOverBudget
}

///|
/// 回溯栈帧：待探索的 (pc, pos, 捕获寄存器快照)。
priv struct BtFrame {
  pc : Int
  pos : Int
  saved : Array[Int]
}

///|
/// 有界回溯搜索（LeftmostFirst 语义）：自 `start` 起做最左优先匹配。
/// `budget` 为 (pc, pos) 状态位图的最大位数；|program| × (|input|+1)
/// 超出预算时返回 `BtOverBudget`（显式、不静默退化）。
pub fn Program::exec_backtrack(
  self : Program,
  input : String,
  start? : Int = 0,
  budget? : Int = BOUNDED_BACKTRACK_BUDGET,
) -> BacktrackResult {
  let chars = input.iter().to_array()
  let n = chars.length()
  let ninst = self.insts.length()
  if ninst * (n + 1) > budget {
    return BtOverBudget
  }
  // visited[pc * (n+1) + pos]：该 (pc, pos) 是否已探索。
  let visited : Array[Bool] = Array::make(ninst * (n + 1), false)
  let slots_len = 2 * (self.num_groups + 1)
  let stack : Array[BtFrame] = []
  // 单遍最左扫描：起点从左到右播种；共享 visited 保证总步数硬上界。
  let mut sp = start
  while sp <= n {
    stack.push({ pc: 0, pos: sp, saved: Array::make(slots_len, -1) })
    while stack.length() > 0 {
      let frame = match stack.pop() {
        Some(f) => f
        None => break
      }
      let pc = frame.pc
      let pos = frame.pos
      let key = pc * (n + 1) + pos
      if visited[key] {
        continue
      }
      visited[key] = true
      match self.insts[pc] {
        IJmp(x) => stack.push({ pc: x, pos, saved: frame.saved })
        ISplit(a, b) => {
          // 栈式 DFS：b 先入栈（后探索），a 后入栈（先探索）→ a 优先。
          stack.push({ pc: b, pos, saved: frame.saved })
          stack.push({ pc: a, pos, saved: frame.saved })
        }
        ISave(slot) => {
          let s2 = copy_ints(frame.saved)
          if slot >= 0 && slot < s2.length() {
            s2[slot] = pos
          }
          stack.push({ pc: pc + 1, pos, saved: s2 })
        }
        IAssert(kind) =>
          if assert_holds(kind, chars, n, pos) {
            stack.push({ pc: pc + 1, pos, saved: frame.saved })
          }
        ILook(positive~, behind~, prog~) =>
          if (if behind {
              prog.run_bool_rev(chars, pos)
            } else {
              prog.run_bool(chars, n, pos)
            }) ==
            positive {
            stack.push({ pc: pc + 1, pos, saved: frame.saved })
          }
        IChar(ch) =>
          if pos < n && chars[pos] == ch {
            stack.push({ pc: pc + 1, pos: pos + 1, saved: frame.saved })
          }
        ISet(cs) =>
          if pos < n && cs.contains(chars[pos].to_int()) {
            stack.push({ pc: pc + 1, pos: pos + 1, saved: frame.saved })
          }
        IMatch => return BtMatch({ slots: frame.saved, names: self.names })
      }
    }
    sp = sp + 1
  }
  BtNoMatch
}

///|
/// meta-engine 策略入口：预算内走有界回溯，超预算自动回退 Pike VM
/// （`LeftmostFirst`），对任意输入总能给出与 Pike VM 一致的结果。
pub fn Program::exec_bounded(
  self : Program,
  input : String,
  start? : Int = 0,
  budget? : Int = BOUNDED_BACKTRACK_BUDGET,
) -> Captures? {
  match self.exec_backtrack(input, start~, budget~) {
    BtMatch(c) => Some(c)
    BtNoMatch => None
    BtOverBudget => self.exec(input, start~, kind=LeftmostFirst)
  }
}
