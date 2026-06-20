// peephole.mbt —— MiniML 字节码窥孔优化（design.md §「Mini-compiler 特性与优化
// 设计」AC2，覆盖 Requirement 9.2 / 9.4）。
//
// 本文件**不修改**任何既有文件与签名，全部能力旁路新增（freeze + bypass）。它
// 消费 bytecode.mbt 的 `Bytecode { instrs : Array[Instr] }` 模型，产出**语义等价
// 且指令数不增加**的优化字节码（`peephole_opt`），供既有 `VM::run` 执行。
//
// ===========================================================================
// 字节码跳转模型回顾（与 bytecode.mbt / vm.mbt 顶部契约一致）
// ===========================================================================
//   * `JumpIfFalse(t)` / `Jump(t)` 的 `t` 是**绝对索引**，直接指向**当前
//     `Bytecode.instrs` 数组**的下标；`t` 亦可等于 `instrs.length()`（表示
//     「跳到末尾之后」即顺序结束当前帧）。
//   * 闭包体 `MkClosure(_, body)` / `MkRecClosure(_, _, body)` 各自携带**独立的**
//     `Bytecode`，其跳转下标只在该体内部有效。故本优化对每个嵌套体**独立递归**
//     优化，绝不跨体改写下标。
//
//   因为「删除指令」会改变其后所有指令的下标，必须**统一重定位（relocate）所有
//   跳转目标**。本文件以「保留位图（keep bitmap）+ 前缀计数重映射」实现安全重定
//   位：对任意原下标 `t`（含末尾 `length`），其新下标 = 原 `[0, t)` 区间中被保留
//   的指令条数。该映射对「被保留指令」给出其新位置、对「被删除指令」给出其后第
//   一条保留指令的位置，二者都正确（删除一条无副作用指令后，原本跳到它的跳转应
//   落到紧随其后的下一条）。
//
// ===========================================================================
// 实现的窥孔规则（均**可证明语义等价**且**指令数不增加**）
// ===========================================================================
//   规则 A「跳转穿透（jump threading）」：对 `Jump(t)` / `JumpIfFalse(t)`，若
//     `instrs[t]` 本身是无条件 `Jump(t2)`，则把目标改写为 `t2`（沿链推进，带环
//     检测）。正确性：执行到中间的无条件 `Jump` 必无条件转移到 `t2` 且**无操作
//     数栈副作用**，故直接以 `t2` 为目标与原行为逐步等价。指令数不变。该规则不
//     直接删指令，但能把跳转规整为「跳到下一条」或令中间跳转变得不可达，从而触
//     发规则 B / C。
//
//   规则 B「跳到下一条消除（jump-to-next elimination）」：对位于下标 `i` 的无条
//     件 `Jump(t)`，若 `t == i + 1`（目标恰为紧邻的下一条），则删除该 `Jump`。
//     正确性：无条件跳到顺序下一条 ≡ 顺序直落（fall-through），且 `Jump` 无栈副
//     作用。**只对无条件 `Jump` 适用**：`JumpIfFalse(i+1)` 仍需弹出栈顶布尔，有
//     副作用，故**不可**当作跳到下一条删除。指令数 -1。
//
//   规则 C「不可达代码消除（unreachable-code elimination）」：从下标 0 出发按控
//     制流做可达性分析（`Jump(t)→{t}`、`JumpIfFalse(t)→{t, i+1}`、`Ret`/越界终止
//     当前帧不再下落、其余 `→{i+1}`），删除所有不可达指令。正确性：永不被执行的
//     指令删除后不改变任何可观测行为。指令数不增。
//
// 三条规则在「不动点（fixpoint）」内反复施加直至字节码稳定：每轮要么删指令（严格
// 减少条数）、要么仅规整跳转目标（穿透幂等），必在有限轮内收敛。三规则联合保证
// **优化后指令数 ≤ 原指令数**（满足 AC2「指令数不增加」），且每步等价（满足 AC4
// 「优化前后求值结果相等」）。

// ---------------------------------------------------------------------------
// 调参常量（命名，避免 magic number）
// ---------------------------------------------------------------------------

///|
/// 不动点迭代轮数的安全松弛量：实际上界取「当前体指令数 + 该松弛量」。每轮要么严
/// 格减少指令数、要么使跳转目标达到穿透幂等，故 `length + 松弛量` 轮足以收敛；该
/// 常量仅作为防御性硬上限，正常情况下远早于此即稳定。
let peephole_round_slack : Int = 2

// ---------------------------------------------------------------------------
// 公开入口
// ---------------------------------------------------------------------------

///|
/// 窥孔优化入口（AC2 / R9.2）：对输入字节码施加可证明等价的窥孔规则，产出**语义
/// 等价且指令数不增加**的优化字节码；优化后用既有 `VM::run` 求值结果不变（AC4 /
/// R9.4）。对每个嵌套闭包体独立递归优化，并正确重定位所有绝对跳转目标。
pub fn peephole_opt(bc : Bytecode) -> Bytecode {
  // 先递归优化所有嵌套闭包体（其跳转下标独立于外层）。
  let lowered : Array[Instr] = []
  for ins in bc.instrs {
    lowered.push(peephole_instr(ins))
  }
  // 再在当前（外层）指令数组上迭代施加规则至不动点。
  let optimized = peephole_fixpoint(lowered)
  Bytecode::{ instrs: optimized }
}

// ---------------------------------------------------------------------------
// 嵌套闭包体递归
// ---------------------------------------------------------------------------

///|
/// 对单条指令：若其携带嵌套闭包体则递归优化该体；其余指令原样返回。
fn peephole_instr(ins : Instr) -> Instr {
  match ins {
    MkClosure(p, body) => MkClosure(p, peephole_opt(body))
    MkRecClosure(f, p, body) => MkRecClosure(f, p, peephole_opt(body))
    other => other
  }
}

// ---------------------------------------------------------------------------
// 不动点驱动
// ---------------------------------------------------------------------------

///|
/// 在当前指令数组上反复施加「穿透 → 跳到下一条消除 → 不可达消除」一轮变换，直到
/// 字节码不再变化或达到防御性轮数上界。返回稳定后的指令数组。
fn peephole_fixpoint(instrs : Array[Instr]) -> Array[Instr] {
  let max_rounds = instrs.length() + peephole_round_slack
  let mut cur = instrs
  let mut round = 0
  while round < max_rounds {
    let next = peephole_one_round(cur)
    // 以 Bytecode 的派生相等比较两轮结果是否一致（结构相等）。
    if Bytecode::{ instrs: next } == Bytecode::{ instrs: cur } {
      break
    }
    cur = next
    round = round + 1
  }
  cur
}

///|
/// 一轮窥孔变换：依次施加规则 A（穿透）、规则 B（跳到下一条消除）、规则 C（不可达
/// 消除）。每个子步都返回语义等价且指令数不增的数组。
fn peephole_one_round(instrs : Array[Instr]) -> Array[Instr] {
  let threaded = thread_jumps(instrs)
  let no_jump_next = remove_jump_to_next(threaded)
  remove_unreachable(no_jump_next)
}

// ---------------------------------------------------------------------------
// 规则 A：跳转穿透（jump threading）
// ---------------------------------------------------------------------------

///|
/// 沿无条件 `Jump` 链解析目标：自 `t` 起，若该处仍是 `Jump(next)` 则继续推进，直到
/// 落在非 `Jump` 指令、越界（`>= length`，即末尾终止）或检测到环为止。`steps` 上界
/// 取数组长度以防多结点环造成的死循环（自环亦在内被截断）。返回最终目标下标。
fn resolve_jump_target(instrs : Array[Instr], t : Int) -> Int {
  let n = instrs.length()
  let mut cur = t
  let mut steps = 0
  while cur >= 0 && cur < n && steps < n {
    match instrs[cur] {
      Jump(next) =>
        if next == cur {
          break // 自环：保持原地，交由可达性分析处理，避免死循环
        } else {
          cur = next
          steps = steps + 1
        }
      _ => break
    }
  }
  cur
}

///|
/// 规则 A：把每条 `Jump` / `JumpIfFalse` 的目标沿无条件 `Jump` 链穿透到最终落点。
/// 指令条数不变，仅改写跳转目标；语义等价（中间无条件跳转无栈副作用）。
fn thread_jumps(instrs : Array[Instr]) -> Array[Instr] {
  let result : Array[Instr] = []
  for ins in instrs {
    match ins {
      Jump(t) => result.push(Jump(resolve_jump_target(instrs, t)))
      JumpIfFalse(t) => result.push(JumpIfFalse(resolve_jump_target(instrs, t)))
      other => result.push(other)
    }
  }
  result
}

// ---------------------------------------------------------------------------
// 规则 B：跳到下一条消除（jump-to-next elimination）
// ---------------------------------------------------------------------------

///|
/// 规则 B：删除位于下标 `i`、目标恰为 `i + 1` 的无条件 `Jump`（顺序直落，等价且无
/// 栈副作用）。`JumpIfFalse` 因有「弹布尔」副作用，即便目标为下一条也**不**删除。
/// 删除后通过 `relocate_jumps` 统一重定位所有跳转目标。
fn remove_jump_to_next(instrs : Array[Instr]) -> Array[Instr] {
  let n = instrs.length()
  let keep = Array::make(n, true)
  for i in 0..<n {
    match instrs[i] {
      Jump(t) => if t == i + 1 { keep[i] = false }
      _ => ()
    }
  }
  relocate_jumps(instrs, keep)
}

// ---------------------------------------------------------------------------
// 规则 C：不可达代码消除（unreachable-code elimination）
// ---------------------------------------------------------------------------

///|
/// 规则 C：从下标 0 起按控制流做可达性标记，删除所有不可达指令。控制流后继：
///   * `Jump(t)`        → 仅 `{t}`（无条件转移，不下落）
///   * `JumpIfFalse(t)` → `{t, i + 1}`（条件转移 + 直落）
///   * `Ret`            → `{}`（结束当前帧，不下落）
///   * 其余指令          → `{i + 1}`（顺序直落）
/// 越界后继（`>= length`）表示帧自然结束，忽略。删除不可达指令不改变可观测行为。
fn remove_unreachable(instrs : Array[Instr]) -> Array[Instr] {
  let n = instrs.length()
  if n == 0 {
    return instrs
  }
  let reachable = Array::make(n, false)
  let worklist : Array[Int] = [0]
  while worklist.length() > 0 {
    let i = match worklist.pop() {
      Some(x) => x
      None => break
    }
    if i < 0 || i >= n || reachable[i] {
      continue
    }
    reachable[i] = true
    match instrs[i] {
      Jump(t) => worklist.push(t)
      JumpIfFalse(t) => {
        worklist.push(t)
        worklist.push(i + 1)
      }
      Ret => () // 帧结束，无后继
      _ => worklist.push(i + 1)
    }
  }
  relocate_jumps(instrs, reachable)
}

// ---------------------------------------------------------------------------
// 安全重定位：保留位图 + 前缀计数重映射
// ---------------------------------------------------------------------------

///|
/// 依据 `keep` 位图删除指令并**统一重定位**所有绝对跳转目标。
///
/// 设 `new_pos[t]` = 原区间 `[0, t)` 中被保留的指令条数（`t` 取 `0 ..= length`）：
///   * 对被保留指令，其新下标即 `new_pos[原下标]`；
///   * 对任意跳转目标 `t`，重映射为 `new_pos[t]`——若 `t` 处指令被保留则得其新位
///     置，否则得其后第一条保留指令的新位置（删除无副作用指令后跳转应顺延至下一
///     条），末尾目标 `length` 映射为保留总条数（仍表示「跳到末尾之后」）。
///
/// 前置条件：`keep.length() == instrs.length()`。返回重定位后的新指令数组。
fn relocate_jumps(instrs : Array[Instr], keep : Array[Bool]) -> Array[Instr] {
  let n = instrs.length()
  // new_pos 含 n + 1 个前缀计数项（最后一项对应末尾目标 length）。
  let new_pos = Array::make(n + 1, 0)
  let mut count = 0
  for i in 0..<n {
    new_pos[i] = count
    if keep[i] {
      count = count + 1
    }
  }
  new_pos[n] = count
  let result : Array[Instr] = []
  for i in 0..<n {
    if keep[i] {
      match instrs[i] {
        Jump(t) => result.push(Jump(new_pos[t]))
        JumpIfFalse(t) => result.push(JumpIfFalse(new_pos[t]))
        other => result.push(other)
      }
    }
  }
  result
}
