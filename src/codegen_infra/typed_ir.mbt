// typed_ir.mbt —— 类型化中间表示（typed IR）数据结构（旗舰深化，旁路新增 / bypass）。
//
// 设计依据（design.md §「Codegen-infra 类型化 IR 设计」，Requirement 7.1）：
// 既有 `BasicBlock { instrs : Array[String] }` 与 `TargetInstr { op : String }`
// 以**字符串化指令**表达 IR，属 anti-patterns 明令禁止的「字符串模拟结构化
// 数据」反模式。本文件在其**平行**位置新增一套**类型化** IR：以精确的枚举
// （`Operand` / `TypedInstr`）与结构体（`TypedBlock` / `TypedFunction`）表达
// 操作数与指令，使非法状态不可表示（ill-typed states unrepresentable）。
//
// 冻结复用原则（只增不减 / freeze + bypass）：本文件**不修改、不删除**任何
// 既有公开签名（既有字符串 IR 全部冻结保留）；类型化 IR 作为独立平行通道，
// 为任务 8.2（IR 验证器 `validate_ir`）与任务 8.3（IR 解释器 `interp_ir`）
// 铺路。本任务仅定义数据结构与少量访问辅助方法，不实现验证器与解释器。
//
// 反模式禁令（遵循 quality-enforcement / anti-patterns 约束）：
//   * 无字符串模拟结构化数据 —— 指令与操作数均为枚举/结构体；
//   * 无 `abort()` / `todo!()` / `panic` 占位 —— 全部方法均有完整实现；
//   * 无 magic number —— 无判定阈值；展示分隔符以命名常量表达；
//   * 无循环内字符串 `+` —— 手写 `Show` 经 `logger.write_string` 直写日志缓冲，
//     不做 `out = out + ...` 累积拼接；
//   * `Show` 一律手写（`derive(Eq)` + `pub impl Show ... with fn output`）以
//     规避 `derive(Debug)` 的弃用告警，与本仓 build_tool / regex 方向一致。

// ───────────────────────────── 命名常量 ─────────────────────────────

///|
/// 手写 `Show` 渲染数组/参数列表时，相邻元素之间的分隔符（避免 magic 字符
/// 散落）。
let show_item_sep : String = ", "

// ───────────────────────────── 操作数 ─────────────────────────────

///|
/// 操作数（operand）—— 指令的输入来源，类型化表达取代字符串：
///
///   * `Reg(Int)` —— 虚拟寄存器编号（SSA 值的承载者）；
///   * `Imm(Int)` —— 立即数（编译期常量）；
///   * `Mem(Int)` —— 内存槽编号（栈/溢出槽寻址）。
///
/// 以 `pub(all)` 暴露构造子，便于宿主、验证器、解释器与属性测试直接构造与
/// 模式匹配（与本包既有 `IrNode` / `Location` / `OptPass` 等的可见性一致）；
/// 派生 `Eq` 支持结构相等比较（验证器去重、解释器状态比对、PBT 反例判定均
/// 依赖之）。
pub(all) enum Operand {
  Reg(Int)
  Imm(Int)
  Mem(Int)
} derive(Eq)

///|
/// 把单个操作数写入日志缓冲（手写 `Show` 的共享渲染器）。
///
/// 抽出为独立函数，供 `Operand` 自身的 `Show` 实现与 `TypedInstr` 的 `Show`
/// 实现复用，避免重复 match；逐字段 `logger.write_string`，无字符串拼接。
fn write_operand(logger : &Logger, op : Operand) -> Unit {
  match op {
    Reg(n) => {
      logger.write_string("Reg(")
      logger.write_string(n.to_string())
      logger.write_string(")")
    }
    Imm(n) => {
      logger.write_string("Imm(")
      logger.write_string(n.to_string())
      logger.write_string(")")
    }
    Mem(n) => {
      logger.write_string("Mem(")
      logger.write_string(n.to_string())
      logger.write_string(")")
    }
  }
}

///|
/// 以可读形式展示操作数（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for Operand with fn output(self : Operand, logger : &Logger) -> Unit {
  write_operand(logger, self)
}

// ───────────────────────────── 类型化指令 ─────────────────────────────

///|
/// 类型化指令（typed instruction）—— 取代 `op : String` 字符串化指令：
///
///   * `Add` / `Sub` / `Mul` —— 二元算术，`dst` 为目标寄存器，`lhs` / `rhs`
///     为操作数；
///   * `Load(dst~, addr~)` —— 从 `addr` 处加载到 `dst`；
///   * `Store(addr~, value~)` —— 将 `value` 写入 `addr`（无目标寄存器）；
///   * `Call(dst~, callee~, args~)` —— 调用 `callee`，实参 `args`，返回值入 `dst`；
///   * `Ret(value~)` —— 返回（`None` 表示无返回值）；
///   * `Br(target~)` —— 无条件跳转到块 `target`；
///   * `CondBr(cond~, then_~, else_~)` —— 条件跳转（`cond` 非零取 `then_`）；
///   * `Phi(dst~, args~)` —— φ 结点，`args` 为「前驱块标签 → 取值操作数」对。
///
/// 命名参数（`dst~` 等）使构造点自带字段名、可读且不易错位；以 `pub(all)`
/// 暴露构造子供验证器/解释器/测试构造与匹配；派生 `Eq` 支撑结构相等
/// （验证器/解释器/PBT 复用）。
pub(all) enum TypedInstr {
  Add(dst~ : Int, lhs~ : Operand, rhs~ : Operand)
  Sub(dst~ : Int, lhs~ : Operand, rhs~ : Operand)
  Mul(dst~ : Int, lhs~ : Operand, rhs~ : Operand)
  Load(dst~ : Int, addr~ : Operand)
  Store(addr~ : Operand, value~ : Operand)
  Call(dst~ : Int, callee~ : String, args~ : Array[Operand])
  Ret(value~ : Operand?)
  Br(target~ : String)
  CondBr(cond~ : Operand, then_~ : String, else_~ : String)
  Phi(dst~ : Int, args~ : Array[(String, Operand)])
} derive(Eq)

///|
/// 渲染二元算术指令的公共骨架（`Add` / `Sub` / `Mul` 复用），手写 `Show` 辅助。
fn write_binop(
  logger : &Logger,
  name : String,
  dst : Int,
  lhs : Operand,
  rhs : Operand,
) -> Unit {
  logger.write_string(name)
  logger.write_string("(dst=")
  logger.write_string(dst.to_string())
  logger.write_string(", lhs=")
  write_operand(logger, lhs)
  logger.write_string(", rhs=")
  write_operand(logger, rhs)
  logger.write_string(")")
}

///|
/// 以可读形式展示类型化指令（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
///
/// 逐字段经 `logger.write_string` / `write_operand` 直写日志缓冲；数组字段
/// （`Call.args` / `Phi.args`）以「首元素无前导分隔符」的方式按序写出，
/// 全程无 `out = out + ...` 循环拼接。
pub impl Show for TypedInstr with fn output(self : TypedInstr, logger : &Logger) -> Unit {
  match self {
    Add(dst~, lhs~, rhs~) => write_binop(logger, "Add", dst, lhs, rhs)
    Sub(dst~, lhs~, rhs~) => write_binop(logger, "Sub", dst, lhs, rhs)
    Mul(dst~, lhs~, rhs~) => write_binop(logger, "Mul", dst, lhs, rhs)
    Load(dst~, addr~) => {
      logger.write_string("Load(dst=")
      logger.write_string(dst.to_string())
      logger.write_string(", addr=")
      write_operand(logger, addr)
      logger.write_string(")")
    }
    Store(addr~, value~) => {
      logger.write_string("Store(addr=")
      write_operand(logger, addr)
      logger.write_string(", value=")
      write_operand(logger, value)
      logger.write_string(")")
    }
    Call(dst~, callee~, args~) => {
      logger.write_string("Call(dst=")
      logger.write_string(dst.to_string())
      logger.write_string(", callee=")
      logger.write_string(callee)
      logger.write_string(", args=[")
      let mut first = true
      for a in args {
        if !first {
          logger.write_string(show_item_sep)
        }
        write_operand(logger, a)
        first = false
      }
      logger.write_string("])")
    }
    Ret(value~) =>
      match value {
        Some(v) => {
          logger.write_string("Ret(")
          write_operand(logger, v)
          logger.write_string(")")
        }
        None => logger.write_string("Ret(None)")
      }
    Br(target~) => {
      logger.write_string("Br(")
      logger.write_string(target)
      logger.write_string(")")
    }
    CondBr(cond~, then_~, else_~) => {
      logger.write_string("CondBr(cond=")
      write_operand(logger, cond)
      logger.write_string(", then=")
      logger.write_string(then_)
      logger.write_string(", else=")
      logger.write_string(else_)
      logger.write_string(")")
    }
    Phi(dst~, args~) => {
      logger.write_string("Phi(dst=")
      logger.write_string(dst.to_string())
      logger.write_string(", args=[")
      let mut first = true
      for pair in args {
        let (label, op) = pair
        if !first {
          logger.write_string(show_item_sep)
        }
        logger.write_string("(")
        logger.write_string(label)
        logger.write_string(", ")
        write_operand(logger, op)
        logger.write_string(")")
        first = false
      }
      logger.write_string("])")
    }
  }
}

///|
/// 该指令定义（写入）的目标寄存器编号（若有）。
///
/// 为任务 8.2 的 SSA 验证（统计每个寄存器的定义次数）与任务 8.3 的解释器
/// （确定写回目标）铺路：
///   * `Add` / `Sub` / `Mul` / `Load` / `Call` / `Phi` —— 定义其 `dst`；
///   * `Store` / `Ret` / `Br` / `CondBr` —— 不定义任何寄存器，返回 `None`。
pub fn TypedInstr::defined_reg(self : TypedInstr) -> Int? {
  match self {
    Add(dst~, ..) => Some(dst)
    Sub(dst~, ..) => Some(dst)
    Mul(dst~, ..) => Some(dst)
    Load(dst~, ..) => Some(dst)
    Call(dst~, ..) => Some(dst)
    Phi(dst~, ..) => Some(dst)
    Store(..) | Ret(..) | Br(..) | CondBr(..) => None
  }
}

///|
/// 该指令是否为基本块终结指令（terminator）。
///
/// 终结指令决定控制流走向，必须且只能出现在基本块末尾（任务 8.2 控制流校验
/// 依据）：`Ret` / `Br` / `CondBr` 为终结指令，其余为普通指令。
pub fn TypedInstr::is_terminator(self : TypedInstr) -> Bool {
  match self {
    Ret(..) | Br(..) | CondBr(..) => true
    Add(..) | Sub(..) | Mul(..) | Load(..) | Store(..) | Call(..) | Phi(..) =>
      false
  }
}

// ───────────────────────────── 基本块与函数 ─────────────────────────────

///|
/// 类型化基本块（typed basic block）：
///
///   * `label` —— 块标签（控制流跳转目标、`Phi` 前驱标识）；
///   * `instrs` —— 块内普通（非终结）指令序列；
///   * `terminator` —— 块终结指令（`None` 表示尚未设置，由验证器在任务 8.2
///     报告为控制流错误）。
///
/// 终结指令独立于 `instrs` 单列，使「每块恰有一个终结点」这一结构约束在类型
/// 层面更显式。以 `pub(all)` 暴露字段，便于验证器/解释器/测试直接读取与构造。
pub(all) struct TypedBlock {
  label : String
  instrs : Array[TypedInstr]
  terminator : TypedInstr?
} derive(Eq)

///|
/// 以可读形式展示基本块（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for TypedBlock with fn output(self : TypedBlock, logger : &Logger) -> Unit {
  logger.write_string("TypedBlock(label=")
  logger.write_string(self.label)
  logger.write_string(", instrs=[")
  let mut first = true
  for ins in self.instrs {
    if !first {
      logger.write_string(show_item_sep)
    }
    Show::output(ins, logger)
    first = false
  }
  logger.write_string("], terminator=")
  match self.terminator {
    Some(t) => Show::output(t, logger)
    None => logger.write_string("None")
  }
  logger.write_string(")")
}

///|
/// 类型化函数（typed function）：
///
///   * `entry` —— 入口块标签（解释器从此开始执行）；
///   * `blocks` —— 全部基本块（顺序无关，按 `label` 寻址）。
///
/// 以 `pub(all)` 暴露字段，便于验证器/解释器/测试直接读取与构造。
pub(all) struct TypedFunction {
  entry : String
  blocks : Array[TypedBlock]
} derive(Eq)

///|
/// 以可读形式展示函数（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for TypedFunction with fn output(
  self : TypedFunction,
  logger : &Logger,
) -> Unit {
  logger.write_string("TypedFunction(entry=")
  logger.write_string(self.entry)
  logger.write_string(", blocks=[")
  let mut first = true
  for b in self.blocks {
    if !first {
      logger.write_string(show_item_sep)
    }
    Show::output(b, logger)
    first = false
  }
  logger.write_string("])")
}

///|
/// 收集函数内全部基本块的标签（保序）。
///
/// 为任务 8.2 控制流校验（跳转目标必须存在于块标签集合）与任务 8.3 解释器
/// （按标签寻址块）铺路。返回新数组，不暴露内部结构。
pub fn TypedFunction::block_labels(self : TypedFunction) -> Array[String] {
  let labels = []
  for b in self.blocks {
    labels.push(b.label)
  }
  labels
}
