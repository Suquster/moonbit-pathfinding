// ir_interp.mbt —— 类型化 IR 解释器（旗舰深化，旁路新增 / bypass）。
//
// 设计依据（design.md §「Codegen-infra 类型化 IR 设计 / IR 解释器」，
// Requirement 7.6 / AC6）：在任务 8.1 的类型化 IR（`Operand` / `TypedInstr` /
// `TypedBlock` / `TypedFunction`）与任务 8.2 的验证器 `validate_ir` 之上，新增
// 一个**确定性**的小步解释器 `interp_ir`：对（通过验证的）IR 按其语义求值，
// 产出一个确定的结果（寄存器终态 + 返回值）。同一 IR 配同一 args 多次解释，
// 结果恒等（任务 8.4 属性验证）。
//
// 冻结复用原则（只增不减 / freeze + bypass）：本文件**不修改、不删除**任何
// 既有公开签名；仅新增 `IrEvalResult` 与 `interp_ir`，复用 8.1 暴露的
// `Operand` / `TypedInstr` / `TypedBlock` / `TypedFunction` 及 8.2 的类型规则
// （值/地址语义与验证器一致）。
//
// 反模式禁令（遵循 quality-enforcement / anti-patterns 约束）：
//   * 无 `abort()` / `todo!()` / `panic` 占位 —— 解释器对任意输入均返回结构化
//     结果；遇验证器本应拦截的非法形态（跳到不存在块、终结字段非终结指令等）
//     时安全停机返回当前状态，而非崩溃；
//   * 无 magic number —— 步数上限以命名常量 `max_steps` 表达，未定义寄存器/
//     内存槽的默认值以命名常量 `default_cell_value` 表达；
//   * 无循环内字符串 `+` —— `Show` 经 `logger.write_string` 直写日志缓冲；
//     `Call` 实参求和为整数累加，非字符串拼接；
//   * 无字符串模拟结构化数据 —— 结果以 `IrEvalResult` 结构体表达；
//   * `Show` 手写（`derive(Eq)` + `pub impl Show ... with fn output`）以规避
//     `derive(Debug)` 弃用告警，与 typed_ir.mbt / ir_validator.mbt 保持一致。

// ───────────────────────────── 命名常量 ─────────────────────────────

///|
/// 解释步数上限：每执行一条指令（含终结指令）计一步，累计步数超过该上限时
/// 解释器**安全停机**并返回当前状态（防止含环控制流的 IR 导致死循环）。
///
/// 取一个足够大的常量，使一切合理规模的（无意环外）IR 都能跑到 `Ret` 或自然
/// 停机；仅在病态/有意构造的无限循环上触顶。命名常量化以杜绝 magic number。
let max_steps : Int = 100_000

///|
/// 未定义寄存器读取、未写入内存槽读取时的默认值。
///
/// 寄存器环境初始仅含入参（args）预置值；读取一个尚未被任何指令定义、且不在
/// args 中的寄存器时，按确定性约定取该默认值（而非崩溃）。内存模型同理：内存
/// 初始为空，读取未写入的槽返回该默认值。命名常量化以杜绝 magic number。
let default_cell_value : Int = 0

// ───────────────────────────── 求值结果 ─────────────────────────────

///|
/// IR 求值结果（解释终态，结构化表达取代散落的返回值）：
///
///   * `regs` —— 解释停机时刻的寄存器环境（寄存器编号 → 值）。初始为 args 的
///     拷贝（入参寄存器预置值），随 `Add` / `Sub` / `Mul` / `Load` / `Call` /
///     `Phi` 等定义类指令写回而演化；解释不修改调用方传入的 `args`（内部先
///     深拷贝）。
///   * `returned` —— 函数返回值：执行到 `Ret(Some(v))` 时为 `Some(求值后的 v)`，
///     执行到 `Ret(None)` 或因触顶/缺终结指令等非正常路径停机时为 `None`。
///
/// 派生 `Eq` 以支持测试与确定性比对（`Map` 的相等与遍历顺序无关，故结果相等性
/// 不受寄存器写入顺序影响）；`Show` 手写以规避 `derive(Debug)` 弃用告警。
pub struct IrEvalResult {
  regs : Map[Int, Int]
  returned : Int?
} derive(Eq)

///|
/// 以可读形式展示求值结果（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
///
/// 逐字段经 `logger.write_string` 直写日志缓冲，无 `out = out + ...` 循环拼接；
/// `regs` 的渲染顺序依 `Map` 遍历顺序（仅用于展示，确定性比对走派生 `Eq`）。
pub impl Show for IrEvalResult with fn output(
  self : IrEvalResult,
  logger : &Logger,
) -> Unit {
  logger.write_string("IrEvalResult(regs={")
  let mut first = true
  for k, v in self.regs {
    if !first {
      logger.write_string(show_item_sep)
    }
    logger.write_string(k.to_string())
    logger.write_string("=>")
    logger.write_string(v.to_string())
    first = false
  }
  logger.write_string("}, returned=")
  match self.returned {
    Some(r) => logger.write_string(r.to_string())
    None => logger.write_string("None")
  }
  logger.write_string(")")
}

// ───────────────────────────── 操作数求值 ─────────────────────────────

///|
/// 把操作数作为「值」求值（用于算术输入、写入值、条件、实参、返回值）：
///
///   * `Reg(r)` —— 取寄存器 `r` 的当前值，未定义则取 `default_cell_value`；
///   * `Imm(v)` —— 立即数本身；
///   * `Mem(m)` —— 取内存槽 `m` 的内容（作「值」时为槽内内容），未写入则取
///     `default_cell_value`。
///
/// 注：按 8.2 的类型规则，裸 `Mem` 不应出现在「值」位置（验证器会报
/// `TypeMismatch`）；此处仍给出确定性语义（取槽内容），以便对未经验证或
/// 部分非法的 IR 亦能确定性停机，而非崩溃。
fn eval_value(
  regs : Map[Int, Int],
  memory : Map[Int, Int],
  op : Operand,
) -> Int {
  match op {
    Reg(r) => regs.get(r).unwrap_or(default_cell_value)
    Imm(v) => v
    Mem(m) => memory.get(m).unwrap_or(default_cell_value)
  }
}

///|
/// 把操作数作为「地址」求值（用于 `Load` / `Store` 的寻址目标，得到内存槽号）：
///
///   * `Mem(m)` —— 槽号即 `m`（`Mem` 作地址时取槽号，与 8.2 类型规则一致）；
///   * `Reg(r)` —— 寄存器 `r` 持有的值即为目标槽号（寄存器存放指针/槽号），
///     未定义则取 `default_cell_value`；
///   * `Imm(v)` —— 立即数作地址（按 8.2 验证器视为非法；此处仍以其字面值作为
///     槽号给出确定性兜底语义）。
fn eval_addr(regs : Map[Int, Int], op : Operand) -> Int {
  match op {
    Mem(m) => m
    Reg(r) => regs.get(r).unwrap_or(default_cell_value)
    Imm(v) => v
  }
}

// ───────────────────────────── 单条指令执行 ─────────────────────────────

///|
/// 执行一条**非终结**指令，就地更新寄存器环境 `regs` 与内存 `memory`。
///
/// 语义（严格按 Requirement 7.6 / 与 8.2 类型规则一致）：
///   * `Add` / `Sub` / `Mul` —— 求值 `lhs` / `rhs`（作值），计算后写回 `dst`；
///   * `Load(dst, addr)` —— 以 `addr`（作地址）为槽号从内存读出，写回 `dst`；
///   * `Store(addr, value)` —— 以 `addr`（作地址）为槽号，将 `value`（作值）写内存；
///   * `Call(dst, callee, args)` —— callee 体未知，采用确定性约定：结果为各实参
///     （作值）之和（空参为 `default_cell_value`），写回 `dst`。该约定保证可
///     复现且对任意 callee 名称稳定；
///   * `Phi(dst, args)` —— 按「来自哪个前驱块」选值：在 `args` 的 (前驱标签,
///     取值) 对中匹配 `prev`（上一个执行的块标签），取首个匹配项求值写回 `dst`；
///     无匹配（如入口块的 Phi，`prev` 为 `None`）则写 `default_cell_value`。
///
/// 终结指令（`Ret` / `Br` / `CondBr`）不应进入此函数（由主循环单独处理）；
/// 若误入则为安全空操作（验证器会在静态阶段拦截「终结指令出现在块体」）。
fn exec_simple(
  regs : Map[Int, Int],
  memory : Map[Int, Int],
  prev : String?,
  ins : TypedInstr,
) -> Unit {
  match ins {
    Add(dst~, lhs~, rhs~) =>
      regs[dst] = eval_value(regs, memory, lhs) + eval_value(regs, memory, rhs)
    Sub(dst~, lhs~, rhs~) =>
      regs[dst] = eval_value(regs, memory, lhs) - eval_value(regs, memory, rhs)
    Mul(dst~, lhs~, rhs~) =>
      regs[dst] = eval_value(regs, memory, lhs) * eval_value(regs, memory, rhs)
    Load(dst~, addr~) =>
      regs[dst] = memory
        .get(eval_addr(regs, addr))
        .unwrap_or(default_cell_value)
    Store(addr~, value~) =>
      memory[eval_addr(regs, addr)] = eval_value(regs, memory, value)
    Call(dst~, args~, ..) => {
      // 确定性约定：未知 callee 的返回值取全部实参（作值）之和（整数累加，
      // 非字符串拼接）；空参列表结果为 default_cell_value。
      let mut acc = default_cell_value
      for a in args {
        acc = acc + eval_value(regs, memory, a)
      }
      regs[dst] = acc
    }
    Phi(dst~, args~) => {
      // 按前驱块标签匹配选值：取首个 (label == prev) 的取值操作数求值。
      let mut chosen = default_cell_value
      match prev {
        Some(p) =>
          for pair in args {
            let (label, op) = pair
            if label == p {
              chosen = eval_value(regs, memory, op)
              break
            }
          }
        None => ()
      }
      regs[dst] = chosen
    }
    // 终结指令不应在块体内出现（验证器拦截）；安全空操作。
    Ret(..) | Br(..) | CondBr(..) => ()
  }
}

// ───────────────────────────── 块寻址 ─────────────────────────────

///|
/// 按标签在函数中查找基本块（线性查找，块数通常很小）。
///
/// 返回 `None` 表示标签不存在（跳到不存在块由 8.2 验证器拦截；解释器据此
/// 安全停机）。
fn find_block(func : TypedFunction, label : String) -> TypedBlock? {
  for b in func.blocks {
    if b.label == label {
      return Some(b)
    }
  }
  None
}

// ───────────────────────────── 顶层解释入口 ─────────────────────────────

///|
/// 解释执行一个类型化函数，产出确定的求值结果（Requirement 7.6 / AC6）。
///
/// 执行模型（小步解释 + 块跳转）：
///   1. 寄存器环境 `regs` 初始化为 `args` 的**拷贝**（入参寄存器预置值，
///      不修改调用方传入的 `args`）；内存 `memory` 初始为空（读未写槽得
///      `default_cell_value`）。
///   2. 从入口块 `func.entry` 开始：顺序执行块内（非终结）指令，再处理块的
///      终结指令决定走向：
///        * `Ret(value?)` —— 设置 `returned` 并停机；
///        * `Br(target)` —— 跳转到 `target`，并记 `prev` 为当前块（供 `Phi`）；
///        * `CondBr(cond, then_, else_)` —— `cond`（作值）非零走 `then_`，
///          否则走 `else_`，同样更新 `prev`。
///   3. 维护 `prev`（上一个执行的块标签）以支持 `Phi` 按前驱选值。
///   4. 步数上限 `max_steps`：每执行一条指令计一步，超限则安全停机返回当前
///      状态（防止含环控制流死循环）。
///   5. 缺终结指令 / 终结字段非终结指令 / 跳到不存在块（均由 8.2 验证器拦截）
///      时安全停机，返回当前 `regs` 与 `returned`（`None`）。
///
/// 确定性：给定相同 `func` 与相同 `args`，多次调用结果恒等（`IrEvalResult`
/// 的 `Eq` 与 `Map` 遍历顺序无关）。
pub fn interp_ir(func : TypedFunction, args~ : Map[Int, Int]) -> IrEvalResult {
  // 深拷贝入参到寄存器环境，避免修改调用方的 args（确定性与无副作用前提）。
  let regs : Map[Int, Int] = Map([])
  for k, v in args {
    regs[k] = v
  }
  let memory : Map[Int, Int] = Map([])
  let mut returned : Int? = None
  let mut current : String? = Some(func.entry)
  let mut prev : String? = None
  let mut steps = 0
  let mut halt = false
  while !halt {
    match current {
      None => halt = true
      Some(lbl) =>
        match find_block(func, lbl) {
          // 跳到不存在块（验证器拦截）：安全停机。
          None => halt = true
          Some(block) => {
            // 顺序执行块内非终结指令。
            for ins in block.instrs {
              steps = steps + 1
              if steps > max_steps {
                halt = true
                break
              }
              exec_simple(regs, memory, prev, ins)
            }
            if !halt {
              // 处理块终结指令。
              match block.terminator {
                // 缺终结指令（验证器拦截）：安全停机。
                None => halt = true
                Some(t) => {
                  steps = steps + 1
                  if steps > max_steps {
                    halt = true
                  } else {
                    match t {
                      Ret(value~) => {
                        returned = match value {
                          Some(v) => Some(eval_value(regs, memory, v))
                          None => None
                        }
                        halt = true
                      }
                      Br(target~) => {
                        prev = Some(lbl)
                        current = Some(target)
                      }
                      CondBr(cond~, then_~, else_~) => {
                        prev = Some(lbl)
                        current = if eval_value(regs, memory, cond) !=
                          default_cell_value {
                          Some(then_)
                        } else {
                          Some(else_)
                        }
                      }
                      // 终结字段持非终结指令（验证器拦截）：安全停机。
                      Add(..)
                      | Sub(..)
                      | Mul(..)
                      | Load(..)
                      | Store(..)
                      | Call(..)
                      | Phi(..) => halt = true
                    }
                  }
                }
              }
            }
          }
        }
    }
  }
  IrEvalResult::{ regs, returned }
}
