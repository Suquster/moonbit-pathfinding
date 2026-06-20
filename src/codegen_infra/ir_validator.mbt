// ir_validator.mbt —— 类型化 IR 验证器（旗舰深化，旁路新增 / bypass）。
//
// 设计依据（design.md §「Codegen-infra 类型化 IR 设计 / IR 验证器」，
// Requirement 7.2 / 7.3 / 7.4 / 7.5）：在任务 8.1 的类型化 IR
// （`Operand` / `TypedInstr` / `TypedBlock` / `TypedFunction`）之上，新增
// 一个**纯函数式**的验证器 `validate_ir`，对一个函数的 IR 做三类静态检查：
//
//   1. SSA 单赋值（AC3）—— 每个虚拟寄存器在整个函数中至多被定义一次；
//   2. 操作数类型一致（AC4）—— 各指令的操作数须满足该指令的「值 / 地址」约束；
//   3. 控制流完整（AC5）—— 入口块存在、每块恰有一个合法终结指令、跳转目标存在。
//
// 合法（满足上述全部约束）的 IR 验证通过（AC2，返回 `Ok(())`）。
//
// 冻结复用原则（只增不减 / freeze + bypass）：本文件**不修改、不删除**任何
// 既有公开签名；仅新增 `IrError` 与 `validate_ir`，复用 8.1 已暴露的
// `defined_reg` / `is_terminator` / `block_labels` 辅助方法。
//
// 反模式禁令（遵循 quality-enforcement / anti-patterns 约束）：
//   * 无 `abort()` / `todo!()` / `panic` 占位 —— 验证器对任意输入均返回结构化结果；
//   * 无 magic number —— SSA 阈值以命名常量 `ssa_max_defs` 表达，期望类型描述
//     与诊断片段均以命名常量表达；
//   * 无循环内字符串 `+` —— 诊断 detail 文本一律经 `StringBuilder` 顺序写入后
//     一次性 `to_string`，不做 `out = out + ...` 累积拼接；
//   * 无字符串模拟结构化数据 —— 错误以 `IrError` 枚举表达；
//   * `Show` 手写（`derive(Eq)` + `pub impl Show ... with fn output`）以规避
//     `derive(Show)` 弃用告警，与 typed_ir.mbt / build_tool 方向保持一致。
//
// 错误收集策略：`validate_ir` **收集函数内的全部错误**后一次性返回
// （不在遇到首个错误时短路），便于一次调用即获得完整诊断列表；当且仅当
// 错误列表为空时返回 `Ok(())`。

// ───────────────────────────── 命名常量 ─────────────────────────────

///|
/// SSA 单赋值上限：每个虚拟寄存器在整个函数中**至多**被定义的次数。
///
/// 取值 `1` 即「静态单赋值」（Static Single Assignment）的定义：一个寄存器
/// 恰有一个定义点。定义计数超过该上限即构成 SSA 违例（AC3）。
let ssa_max_defs : Int = 1

///|
/// 类型诊断中「值类操作数」的期望描述：算术 / 写入值 / 条件 / 实参 / 返回值
/// 等位置要求操作数承载一个**可计算的值**，合法形态为 `Reg`（寄存器中的 SSA
/// 值）或 `Imm`（立即数）。裸 `Mem`（内存槽）不是值，必须先 `Load` 取出。
let value_kinds_desc : String = "value operand (Reg or Imm)"

///|
/// 类型诊断中「地址类操作数」的期望描述：`Load` / `Store` 的地址位置要求一个
/// **可寻址目标**，合法形态为 `Mem`（内存槽）或 `Reg`（寄存器中持有的指针）。
/// `Imm`（立即数）作为读写目标地址非法。
let address_kinds_desc : String = "address operand (Reg or Mem)"

// ───────────────────────────── 错误类型 ─────────────────────────────

///|
/// IR 验证错误（结构化诊断，取代字符串化报告）：
///
///   * `SsaViolation(reg~)` —— 寄存器 `reg` 在函数中被定义超过一次（违反 SSA，AC3）；
///   * `TypeMismatch(instr~, detail~)` —— 指令 `instr` 的某操作数类型与该指令
///     要求不一致（AC4），`detail` 描述「哪个位置是什么、期望什么」；
///   * `ControlFlowError(block~, detail~)` —— 块 `block` 的控制流不完整（缺终结
///     指令、终结指令位置非法、跳转目标不存在，或入口块缺失，AC5）。
///
/// 派生 `Eq` 以支持测试与去重比较；`Show` 手写以规避 `derive(Show)` 弃用告警。
pub enum IrError {
  SsaViolation(reg~ : Int)
  TypeMismatch(instr~ : String, detail~ : String)
  ControlFlowError(block~ : String, detail~ : String)
} derive(Eq)

///|
/// 以可读形式展示验证错误（手写 `Show`，规避 `derive(Show)` 弃用告警）。
pub impl Show for IrError with fn output(self : IrError, logger : &Logger) -> Unit {
  match self {
    SsaViolation(reg~) => {
      logger.write_string("SsaViolation(reg=")
      logger.write_string(reg.to_string())
      logger.write_string(")")
    }
    TypeMismatch(instr~, detail~) => {
      logger.write_string("TypeMismatch(instr=")
      logger.write_string(instr)
      logger.write_string(", detail=")
      logger.write_string(detail)
      logger.write_string(")")
    }
    ControlFlowError(block~, detail~) => {
      logger.write_string("ControlFlowError(block=")
      logger.write_string(block)
      logger.write_string(", detail=")
      logger.write_string(detail)
      logger.write_string(")")
    }
  }
}

// ───────────────────────────── 操作数类型判定 ─────────────────────────────

///|
/// 操作数是否为「值」（可作为算术输入 / 写入值 / 条件 / 实参 / 返回值）：
/// `Reg` / `Imm` 为值，`Mem` 不是值（须先 `Load`）。
fn operand_is_value(op : Operand) -> Bool {
  match op {
    Reg(_) | Imm(_) => true
    Mem(_) => false
  }
}

///|
/// 操作数是否为「地址」（可作为 `Load` / `Store` 的寻址目标）：
/// `Mem`（内存槽）或 `Reg`（持有指针的寄存器）为地址，`Imm` 不是地址。
fn operand_is_address(op : Operand) -> Bool {
  match op {
    Reg(_) | Mem(_) => true
    Imm(_) => false
  }
}

///|
/// 操作数构造子名称（用于诊断 detail 文本）。
fn operand_kind_name(op : Operand) -> String {
  match op {
    Reg(_) => "Reg"
    Imm(_) => "Imm"
    Mem(_) => "Mem"
  }
}

///|
/// 指令助记符（用于 `TypeMismatch.instr` 字段）。
fn instr_mnemonic(instr : TypedInstr) -> String {
  match instr {
    Add(..) => "Add"
    Sub(..) => "Sub"
    Mul(..) => "Mul"
    Load(..) => "Load"
    Store(..) => "Store"
    Call(..) => "Call"
    Ret(..) => "Ret"
    Br(..) => "Br"
    CondBr(..) => "CondBr"
    Phi(..) => "Phi"
  }
}

// ───────────────────────────── 诊断文本构建 ─────────────────────────────

///|
/// 构建类型不一致的 detail 文本（经 `StringBuilder` 顺序写入，无循环拼接）：
/// 形如 `"<role> is Mem, expected value operand (Reg or Imm)"`。
fn type_detail(role : String, op : Operand, expected : String) -> String {
  let sb = StringBuilder::new()
  sb.write_string(role)
  sb.write_string(" is ")
  sb.write_string(operand_kind_name(op))
  sb.write_string(", expected ")
  sb.write_string(expected)
  sb.to_string()
}

///|
/// 构建「跳转目标不存在」的 detail 文本：形如 `"jump target 'L9' not found"`。
fn missing_target_detail(target : String) -> String {
  let sb = StringBuilder::new()
  sb.write_string("jump target '")
  sb.write_string(target)
  sb.write_string("' not found")
  sb.to_string()
}

// ───────────────────────────── SSA 校验（AC3） ─────────────────────────────

///|
/// 累计单个寄存器的定义次数；当次数恰好越过 SSA 上限（首次达到
/// `ssa_max_defs + 1`）时记录一次 `SsaViolation`，确保同一寄存器即便被定义
/// 三次及以上也只报告一次。
fn record_def(
  counts : Map[Int, Int],
  errors : Array[IrError],
  reg : Int,
) -> Unit {
  let c = counts.get(reg).unwrap_or(0) + 1
  counts[reg] = c
  if c == ssa_max_defs + 1 {
    errors.push(SsaViolation(reg~))
  }
}

///|
/// 校验 SSA 单赋值（AC3）：遍历全部块的普通指令与终结指令，统计每个被定义
/// 寄存器（由 `defined_reg` 给出）的定义次数，定义超过一次者报 `SsaViolation`。
fn check_ssa(func : TypedFunction, errors : Array[IrError]) -> Unit {
  let counts : Map[Int, Int] = Map([])
  for b in func.blocks {
    for ins in b.instrs {
      match ins.defined_reg() {
        Some(r) => record_def(counts, errors, r)
        None => ()
      }
    }
    match b.terminator {
      Some(t) =>
        match t.defined_reg() {
          Some(r) => record_def(counts, errors, r)
          None => ()
        }
      None => ()
    }
  }
}

// ───────────────────────────── 类型校验（AC4） ─────────────────────────────

///|
/// 校验二元算术指令（`Add` / `Sub` / `Mul`）的操作数：`lhs` / `rhs` 均须为值
/// （`Reg` / `Imm`）；裸 `Mem` 非法（须先 `Load`）。
fn check_binop(
  name : String,
  lhs : Operand,
  rhs : Operand,
  errors : Array[IrError],
) -> Unit {
  if !operand_is_value(lhs) {
    errors.push(
      TypeMismatch(instr=name, detail=type_detail("lhs", lhs, value_kinds_desc)),
    )
  }
  if !operand_is_value(rhs) {
    errors.push(
      TypeMismatch(instr=name, detail=type_detail("rhs", rhs, value_kinds_desc)),
    )
  }
}

///|
/// 校验单条指令的操作数类型一致性（AC4）。类型规则（自洽、可解释）：
///
///   * `Add` / `Sub` / `Mul`：`lhs` / `rhs` 须为值（`Reg` / `Imm`）；`Mem` 非法。
///   * `Load`：`addr` 须为地址（`Reg` / `Mem`）；`Imm` 作地址非法。
///   * `Store`：`addr` 须为地址（`Reg` / `Mem`，`Imm` 非法）；`value` 须为值
///     （`Reg` / `Imm`，`Mem` 非法）。
///   * `Call`：`callee` 名称非空；每个实参 `args[i]` 须为值（`Mem` 非法）。
///   * `Ret`：若有返回值，则须为值（`Mem` 非法）。
///   * `CondBr`：`cond` 须为值（条件由计算得到，`Mem` 非法）。
///   * `Phi`：每个来路取值须为值（`Mem` 非法）。
///   * `Br`：无操作数类型约束。
fn check_instr_types(instr : TypedInstr, errors : Array[IrError]) -> Unit {
  let name = instr_mnemonic(instr)
  match instr {
    Add(lhs~, rhs~, ..) => check_binop(name, lhs, rhs, errors)
    Sub(lhs~, rhs~, ..) => check_binop(name, lhs, rhs, errors)
    Mul(lhs~, rhs~, ..) => check_binop(name, lhs, rhs, errors)
    Load(addr~, ..) =>
      if !operand_is_address(addr) {
        errors.push(
          TypeMismatch(
            instr=name,
            detail=type_detail("addr", addr, address_kinds_desc),
          ),
        )
      }
    Store(addr~, value~) => {
      if !operand_is_address(addr) {
        errors.push(
          TypeMismatch(
            instr=name,
            detail=type_detail("addr", addr, address_kinds_desc),
          ),
        )
      }
      if !operand_is_value(value) {
        errors.push(
          TypeMismatch(
            instr=name,
            detail=type_detail("value", value, value_kinds_desc),
          ),
        )
      }
    }
    Call(callee~, args~, ..) => {
      if callee == "" {
        errors.push(TypeMismatch(instr=name, detail="callee name is empty"))
      }
      for a in args {
        if !operand_is_value(a) {
          errors.push(
            TypeMismatch(
              instr=name,
              detail=type_detail("arg", a, value_kinds_desc),
            ),
          )
        }
      }
    }
    Ret(value~) =>
      match value {
        Some(v) =>
          if !operand_is_value(v) {
            errors.push(
              TypeMismatch(
                instr=name,
                detail=type_detail("ret value", v, value_kinds_desc),
              ),
            )
          }
        None => ()
      }
    CondBr(cond~, ..) =>
      if !operand_is_value(cond) {
        errors.push(
          TypeMismatch(
            instr=name,
            detail=type_detail("cond", cond, value_kinds_desc),
          ),
        )
      }
    Phi(args~, ..) =>
      for pair in args {
        let (_, op) = pair
        if !operand_is_value(op) {
          errors.push(
            TypeMismatch(
              instr=name,
              detail=type_detail("phi arg", op, value_kinds_desc),
            ),
          )
        }
      }
    Br(..) => ()
  }
}

// ───────────────────────────── 控制流校验（AC5） ─────────────────────────────

///|
/// 校验终结指令的跳转目标存在性：`Br.target` / `CondBr.then_` / `CondBr.else_`
/// 必须出现在函数的块标签集合 `labels` 中；否则报 `ControlFlowError`。
fn check_jump_targets(
  block : String,
  term : TypedInstr,
  labels : Map[String, Bool],
  errors : Array[IrError],
) -> Unit {
  match term {
    Br(target~) =>
      if !labels.contains(target) {
        errors.push(
          ControlFlowError(block~, detail=missing_target_detail(target)),
        )
      }
    CondBr(then_~, else_~, ..) => {
      if !labels.contains(then_) {
        errors.push(
          ControlFlowError(block~, detail=missing_target_detail(then_)),
        )
      }
      if !labels.contains(else_) {
        errors.push(
          ControlFlowError(block~, detail=missing_target_detail(else_)),
        )
      }
    }
    _ => ()
  }
}

///|
/// 校验控制流完整性（AC5）。数据模型约定：终结指令独立存放于 `TypedBlock`
/// 的 `terminator` 字段，`instrs` 仅含普通（非终结）指令。据此校验：
///
///   * 入口块 `func.entry` 必须存在于块标签集合中；
///   * 每个块的 `terminator` 必须非空（缺终结指令报错）；
///   * `terminator` 字段所持必须确为终结指令（`Ret` / `Br` / `CondBr`）；
///   * `Br` / `CondBr` 的跳转目标块必须存在；
///   * `instrs` 内不得混入终结指令（终结指令只能位于 `terminator`）。
fn check_control_flow(func : TypedFunction, errors : Array[IrError]) -> Unit {
  let labels : Map[String, Bool] = Map([])
  for lbl in func.block_labels() {
    labels[lbl] = true
  }
  if !labels.contains(func.entry) {
    errors.push(
      ControlFlowError(block=func.entry, detail="entry block not found"),
    )
  }
  for b in func.blocks {
    match b.terminator {
      None =>
        errors.push(
          ControlFlowError(block=b.label, detail="missing terminator"),
        )
      Some(t) => {
        if !t.is_terminator() {
          errors.push(
            ControlFlowError(
              block=b.label,
              detail="terminator field holds a non-terminator instruction",
            ),
          )
        }
        check_jump_targets(b.label, t, labels, errors)
      }
    }
    for ins in b.instrs {
      if ins.is_terminator() {
        errors.push(
          ControlFlowError(
            block=b.label,
            detail="terminator instruction appears in block body",
          ),
        )
      }
    }
  }
}

// ───────────────────────────── 顶层验证入口 ─────────────────────────────

///|
/// 验证一个类型化函数的 IR，**收集全部错误**后返回：
///
///   * 无任何错误 → `Ok(())`（AC2：合法 SSA 的 IR 验证通过）；
///   * 否则 → `Err(errors)`，`errors` 含本次发现的所有 `IrError`
///     （SSA 违例、类型不一致、控制流错误），不在首个错误处短路。
///
/// 三类检查相互独立、各自全量遍历，便于一次调用即得到完整诊断。
pub fn validate_ir(func : TypedFunction) -> Result[Unit, Array[IrError]] {
  let errors : Array[IrError] = []
  check_ssa(func, errors)
  check_control_flow(func, errors)
  for b in func.blocks {
    for ins in b.instrs {
      check_instr_types(ins, errors)
    }
    match b.terminator {
      Some(t) => check_instr_types(t, errors)
      None => ()
    }
  }
  if errors.length() == 0 {
    Ok(())
  } else {
    Err(errors)
  }
}
