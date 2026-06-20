// typed_ir_prop_wbtest.mbt —— 类型化 IR 正确性属性测试（任务 8.4，白盒）。
//
// 设计依据（design.md §「正确性属性」Property 7，Requirement 7.2/7.3/7.4/7.5/7.6）：
//   Property 7（R7 IR 正确性）—— 合法 SSA 验证通过；重复定义→SsaViolation；
//   类型不符→TypeMismatch；控制流缺失→ControlFlowError；解释器对通过验证的
//   IR 求值结果确定。
//
// 置于白盒测试（`_wbtest.mbt`，与被测代码同包）的原因：本套属性需断言
// `IrError` 的具体变体（`SsaViolation` / `TypeMismatch` / `ControlFlowError`），
// 而 `IrError` 以 `pub`（包外只读）暴露，其构造子与模式匹配仅在包内可用；
// 同时白盒环境可不带 `@codegen_infra.` 前缀直接构造 `TypedFunction` /
// `TypedInstr` / `Operand`，并共享同一套「合法函数生成器」，避免跨黑盒/白盒
// 包重复定义生成器。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板；每条属性
// 显式传入 `iters=100`（≥100 次迭代，满足质量门槛）。
//
// 反模式禁令（遵循 quality-enforcement / anti-patterns 约束）：
//   * 无循环内字符串 `+` —— 块标签 / callee 名称均为命名常量或字面量，无累积拼接；
//   * 无 `abort()` / `todo!()` / `panic` 占位 —— 谓词对任意输入均返回 Bool；
//   * 无 magic number —— 生成器规模与取值范围以命名常量表达；
//   * 断言统一以 `assert_true` + 派生 `Eq` / `match` 表达，规避核心库 `Show`
//     弃用告警，使本文件零告警。

// ───────────────────────────── 生成器规模常量 ─────────────────────────────

///|
/// 合法函数生成：单个块内非终结指令条数上限（`0 ..= pbt_max_block_instrs`）。
/// 规模刻意保持较小，使三后端测试在合理时间内完成，同时覆盖「空块 / 多指令块」。
let pbt_max_block_instrs : Int = 3

///|
/// 合法函数生成：立即数（`Imm`）取值范围 `[-pbt_imm_bound, pbt_imm_bound]`。
let pbt_imm_bound : Int = 8

///|
/// 合法函数生成：内存槽号（`Mem`）取值范围 `[0, pbt_mem_bound]`。
let pbt_mem_bound : Int = 7

///|
/// 合法函数生成：`Call` 实参个数上限（`0 ..= pbt_max_call_args`）。
let pbt_max_call_args : Int = 2

///|
/// 解释器确定性属性：随机入参寄存器编号上限（`0 ..= pbt_arg_reg_bound`）。
let pbt_arg_reg_bound : Int = 5

///|
/// 解释器确定性属性：随机入参 Map 的条目数上限（`0 ..= pbt_max_args`）。
let pbt_max_args : Int = 4

///|
/// 直线 add 解释正确性属性：操作数取值范围 `[-pbt_add_bound, pbt_add_bound]`。
let pbt_add_bound : Int = 50

///|
/// SSA 违例生成：被重复定义的寄存器编号取值范围 `[1, pbt_dup_reg_bound]`。
let pbt_dup_reg_bound : Int = 20

///|
/// 入口块标签（控制流起点，命名常量化以杜绝散落字面量）。
let pbt_label_b0 : String = "b0"

///|
/// 第二个块标签（双块函数的后继块）。
let pbt_label_b1 : String = "b1"

///|
/// `Call` 指令的占位被调名称（非空即满足验证器对 callee 的约束）。
let pbt_callee : String = "f"

// ───────────────────────────── 合法操作数生成 ─────────────────────────────

///|
/// 生成一个「值」操作数（`Reg` / `Imm`，二者均为验证器认可的值类操作数）。
///
/// 若已有定义过的寄存器（`defined` 非空）则以约 50% 概率引用其一（`Reg`），
/// 否则生成立即数（`Imm`）。无论如何都不会产生裸 `Mem`，从而保证算术 / 写入值
/// / 条件 / 实参 / 返回值等「值位置」类型合法（AC4）。
fn pbt_value_operand(rng : @infra_pbt.Rng, defined : Array[Int]) -> Operand {
  if defined.length() > 0 && rng.next_bool() {
    Reg(defined[rng.next_below(defined.length())])
  } else {
    Imm(rng.next_range(-pbt_imm_bound, pbt_imm_bound))
  }
}

///|
/// 生成一个「地址」操作数（`Reg` / `Mem`，二者均为验证器认可的地址类操作数）。
///
/// 若已有定义过的寄存器则以约 50% 概率引用其一（寄存器持有指针），否则生成
/// 内存槽（`Mem`）。无论如何都不会产生 `Imm`，从而保证 `Load` / `Store` 的
/// 寻址位置类型合法（AC4）。
fn pbt_addr_operand(rng : @infra_pbt.Rng, defined : Array[Int]) -> Operand {
  if defined.length() > 0 && rng.next_bool() {
    Reg(defined[rng.next_below(defined.length())])
  } else {
    Mem(rng.next_range(0, pbt_mem_bound))
  }
}

// ───────────────────────────── 合法块体生成 ─────────────────────────────

///|
/// 生成一个块的「非终结」指令序列（保证 SSA 与类型合法）。
///
///   * `counter` 为长度 1 的可变单元，持有「下一个新鲜寄存器号」，每个定义类
///     指令取一个全函数唯一的 `dst`（保证 SSA 单赋值，AC3 的对立面——合法函数
///     绝不重复定义）；
///   * `defined` 累积已定义的寄存器号，供后续操作数引用；新定义在指令构造
///     **之后**才追加，故操作数仅引用更早的定义；
///   * 选取的指令均为非终结指令（`Add` / `Sub` / `Mul` / `Load` / `Store` /
///     `Call` / `Phi`），且操作数经 `pbt_value_operand` / `pbt_addr_operand`
///     构造，类型恒合法。
fn pbt_gen_instrs(
  rng : @infra_pbt.Rng,
  counter : Array[Int],
  defined : Array[Int],
) -> Array[TypedInstr] {
  let n = rng.next_range(0, pbt_max_block_instrs)
  let instrs : Array[TypedInstr] = []
  for _i in 0..<n {
    let choice = rng.next_below(7)
    if choice == 0 {
      let d = counter[0]
      counter[0] = d + 1
      instrs.push(
        Add(
          dst=d,
          lhs=pbt_value_operand(rng, defined),
          rhs=pbt_value_operand(rng, defined),
        ),
      )
      defined.push(d)
    } else if choice == 1 {
      let d = counter[0]
      counter[0] = d + 1
      instrs.push(
        Sub(
          dst=d,
          lhs=pbt_value_operand(rng, defined),
          rhs=pbt_value_operand(rng, defined),
        ),
      )
      defined.push(d)
    } else if choice == 2 {
      let d = counter[0]
      counter[0] = d + 1
      instrs.push(
        Mul(
          dst=d,
          lhs=pbt_value_operand(rng, defined),
          rhs=pbt_value_operand(rng, defined),
        ),
      )
      defined.push(d)
    } else if choice == 3 {
      let d = counter[0]
      counter[0] = d + 1
      instrs.push(Load(dst=d, addr=pbt_addr_operand(rng, defined)))
      defined.push(d)
    } else if choice == 4 {
      // Store 无目标寄存器，不消耗 counter。
      instrs.push(
        Store(
          addr=pbt_addr_operand(rng, defined),
          value=pbt_value_operand(rng, defined),
        ),
      )
    } else if choice == 5 {
      let d = counter[0]
      counter[0] = d + 1
      let ac = rng.next_range(0, pbt_max_call_args)
      let args : Array[Operand] = []
      for _j in 0..<ac {
        args.push(pbt_value_operand(rng, defined))
      }
      instrs.push(Call(dst=d, callee=pbt_callee, args~))
      defined.push(d)
    } else {
      // choice == 6：Phi —— 来路取值均为「值」操作数，类型合法（前驱标签
      // 存在性不在验证器约束内，取 b0/b1 字面量即可）。
      let d = counter[0]
      counter[0] = d + 1
      let pc = rng.next_range(1, 2)
      let pairs : Array[(String, Operand)] = []
      for _j in 0..<pc {
        let lbl = if rng.next_bool() { pbt_label_b0 } else { pbt_label_b1 }
        pairs.push((lbl, pbt_value_operand(rng, defined)))
      }
      instrs.push(Phi(dst=d, args=pairs))
      defined.push(d)
    }
  }
  instrs
}

// ───────────────────────────── 合法函数生成器 ─────────────────────────────

///|
/// 生成一个**保证合法**（通过 `validate_ir`）的随机类型化函数。
///
/// 结构（单块或双块，由随机 bool 决定）：
///   * 单块：`b0` 含随机合法非终结指令 + `Ret`（有/无返回值）；
///   * 双块：`b0` 以 `Br("b1")` 或 `CondBr(cond, then="b1", else="b1")` 终结
///     （两分支均指向存在的 `b1`，既保证跳转目标存在，又避免回边导致解释器
///     长循环）；`b1` 含随机合法非终结指令 + `Ret`。
///
/// 合法性保证：SSA（全函数共享 `counter` 取唯一 `dst`）、类型（操作数经
/// 合法构造器生成）、控制流（入口 `b0` 存在、每块恰一个合法终结指令、跳转目标
/// 存在、块体不含终结指令）。
fn gen_legal_function() -> @infra_pbt.Gen[TypedFunction] {
  @infra_pbt.Gen::new(fn(rng) {
    let counter = [1]
    let defined : Array[Int] = []
    let b0_instrs = pbt_gen_instrs(rng, counter, defined)
    if rng.next_bool() {
      // 双块函数：b0 跳转到 b1，b1 以 Ret 收尾。
      let b0_term : TypedInstr = if rng.next_bool() {
        Br(target=pbt_label_b1)
      } else {
        CondBr(
          cond=pbt_value_operand(rng, defined),
          then_=pbt_label_b1,
          else_=pbt_label_b1,
        )
      }
      let b0 = TypedBlock::{
        label: pbt_label_b0,
        instrs: b0_instrs,
        terminator: Some(b0_term),
      }
      let b1_instrs = pbt_gen_instrs(rng, counter, defined)
      let b1_ret : TypedInstr = if rng.next_bool() {
        Ret(value=Some(pbt_value_operand(rng, defined)))
      } else {
        Ret(value=None)
      }
      let b1 = TypedBlock::{
        label: pbt_label_b1,
        instrs: b1_instrs,
        terminator: Some(b1_ret),
      }
      TypedFunction::{ entry: pbt_label_b0, blocks: [b0, b1] }
    } else {
      // 单块函数：b0 以 Ret 收尾。
      let ret : TypedInstr = if rng.next_bool() {
        Ret(value=Some(pbt_value_operand(rng, defined)))
      } else {
        Ret(value=None)
      }
      let b0 = TypedBlock::{
        label: pbt_label_b0,
        instrs: b0_instrs,
        terminator: Some(ret),
      }
      TypedFunction::{ entry: pbt_label_b0, blocks: [b0] }
    }
  })
}

///|
/// 在合法函数之上附加一份随机入参 Map（供解释器确定性属性使用）。
fn gen_legal_function_with_args() -> @infra_pbt.Gen[
  (TypedFunction, Map[Int, Int]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let func = gen_legal_function().generate(rng)
    let args : Map[Int, Int] = Map([])
    let ac = rng.next_range(0, pbt_max_args)
    for _i in 0..<ac {
      let k = rng.next_range(0, pbt_arg_reg_bound)
      let v = rng.next_range(-pbt_imm_bound, pbt_imm_bound)
      args[k] = v
    }
    (func, args)
  })
}

// ───────────────────────────── 反例生成器 ─────────────────────────────

///|
/// 生成「同一寄存器被定义两次」的非法函数（仅含 SSA 缺陷，其余合法）。
///
/// 形如 `b0: r = Imm + Imm; r = Imm * Imm; ret r`，随机化寄存器号 `r` 与各
/// 立即数，附带返回 `r` 以供断言。
fn gen_dup_def() -> @infra_pbt.Gen[(TypedFunction, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let r = rng.next_range(1, pbt_dup_reg_bound)
    let a = rng.next_range(-pbt_imm_bound, pbt_imm_bound)
    let b = rng.next_range(-pbt_imm_bound, pbt_imm_bound)
    let c = rng.next_range(-pbt_imm_bound, pbt_imm_bound)
    let dd = rng.next_range(-pbt_imm_bound, pbt_imm_bound)
    let block = TypedBlock::{
      label: pbt_label_b0,
      instrs: [
        Add(dst=r, lhs=Imm(a), rhs=Imm(b)),
        Mul(dst=r, lhs=Imm(c), rhs=Imm(dd)),
      ],
      terminator: Some(Ret(value=Some(Reg(r)))),
    }
    (TypedFunction::{ entry: pbt_label_b0, blocks: [block] }, r)
  })
}

///|
/// 生成「操作数类型违规」的非法函数（仅含类型缺陷，其余合法）。
///
/// 在三种违规形态间随机选择：
///   * `Store` 以 `Imm` 作写入地址（地址位置不接受立即数）；
///   * `Add` 以 `Mem` 作算术操作数（值位置不接受裸内存槽）；
///   * `Load` 以 `Imm` 作读取地址（地址位置不接受立即数）。
fn gen_type_violation() -> @infra_pbt.Gen[TypedFunction] {
  @infra_pbt.Gen::new(fn(rng) {
    let kind = rng.next_below(3)
    let bad : TypedInstr = if kind == 0 {
      Store(
        addr=Imm(rng.next_range(0, pbt_mem_bound)),
        value=Imm(rng.next_range(-pbt_imm_bound, pbt_imm_bound)),
      )
    } else if kind == 1 {
      Add(
        dst=1,
        lhs=Mem(rng.next_range(0, pbt_mem_bound)),
        rhs=Imm(rng.next_range(-pbt_imm_bound, pbt_imm_bound)),
      )
    } else {
      Load(dst=1, addr=Imm(rng.next_range(0, pbt_mem_bound)))
    }
    let block = TypedBlock::{
      label: pbt_label_b0,
      instrs: [bad],
      terminator: Some(Ret(value=None)),
    }
    TypedFunction::{ entry: pbt_label_b0, blocks: [block] }
  })
}

///|
/// 生成「控制流缺失」的非法函数（仅含控制流缺陷，其余合法）。
///
/// 在两种形态间随机选择：
///   * 跳转到不存在的块（目标取自一组保证不在块标签集合中的字面量）；
///   * 块缺失终结指令（`terminator: None`）。
fn gen_cfg_violation() -> @infra_pbt.Gen[TypedFunction] {
  @infra_pbt.Gen::new(fn(rng) {
    if rng.next_bool() {
      // 跳转到不存在的块（"zzz*" 均不等于唯一块标签 b0）。
      let targets = ["zzz0", "zzz1", "zzz2"]
      let t = targets[rng.next_below(targets.length())]
      let block = TypedBlock::{
        label: pbt_label_b0,
        instrs: [],
        terminator: Some(Br(target=t)),
      }
      TypedFunction::{ entry: pbt_label_b0, blocks: [block] }
    } else {
      // 缺失终结指令。
      let block = TypedBlock::{
        label: pbt_label_b0,
        instrs: [
          Add(
            dst=1,
            lhs=Imm(rng.next_range(-pbt_imm_bound, pbt_imm_bound)),
            rhs=Imm(rng.next_range(-pbt_imm_bound, pbt_imm_bound)),
          ),
        ],
        terminator: None,
      }
      TypedFunction::{ entry: pbt_label_b0, blocks: [block] }
    }
  })
}

///|
/// 直线 add 函数 + 期望值生成器：`b0: r1 = Imm(a) + Imm(b); ret r1`，期望
/// 返回 `a + b`。
fn gen_add_case() -> @infra_pbt.Gen[(Int, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    (
      rng.next_range(-pbt_add_bound, pbt_add_bound),
      rng.next_range(-pbt_add_bound, pbt_add_bound),
    )
  })
}

// ───────────────────────────── 谓词 ─────────────────────────────

///|
/// 谓词：合法函数 `validate_ir` 返回 `Ok`。
fn pbt_legal_validates(func : TypedFunction) -> Bool {
  match validate_ir(func) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// 谓词：重复定义的函数 `validate_ir` 返回 `Err` 且含 `SsaViolation(reg=r)`。
fn pbt_has_ssa_violation(input : (TypedFunction, Int)) -> Bool {
  let (func, r) = input
  match validate_ir(func) {
    Ok(_) => false
    Err(errs) => errs.contains(SsaViolation(reg=r))
  }
}

///|
/// 谓词：类型违规的函数 `validate_ir` 返回 `Err` 且含某个 `TypeMismatch`。
fn pbt_has_type_mismatch(func : TypedFunction) -> Bool {
  match validate_ir(func) {
    Ok(_) => false
    Err(errs) => {
      let mut found = false
      for e in errs {
        match e {
          TypeMismatch(..) => found = true
          _ => ()
        }
      }
      found
    }
  }
}

///|
/// 谓词：控制流缺失的函数 `validate_ir` 返回 `Err` 且含某个 `ControlFlowError`。
fn pbt_has_control_flow_error(func : TypedFunction) -> Bool {
  match validate_ir(func) {
    Ok(_) => false
    Err(errs) => {
      let mut found = false
      for e in errs {
        match e {
          ControlFlowError(..) => found = true
          _ => ()
        }
      }
      found
    }
  }
}

///|
/// 谓词：解释器对同一函数 + 同一入参两次求值结果完全相等（确定性）。
fn pbt_interp_deterministic(input : (TypedFunction, Map[Int, Int])) -> Bool {
  let (func, args) = input
  interp_ir(func, args~) == interp_ir(func, args~)
}

///|
/// 谓词：直线 add 函数解释结果等于手算 `a + b`。
fn pbt_add_interp_correct(p : (Int, Int)) -> Bool {
  let (a, b) = p
  let block = TypedBlock::{
    label: pbt_label_b0,
    instrs: [Add(dst=1, lhs=Imm(a), rhs=Imm(b))],
    terminator: Some(Ret(value=Some(Reg(1)))),
  }
  let func = TypedFunction::{ entry: pbt_label_b0, blocks: [block] }
  interp_ir(func, args=Map([])).returned == Some(a + b)
}

// ───────────────────────────── 属性测试 ─────────────────────────────

///|
/// Feature: production-hardening, Property 7: 合法 SSA 的 IR 验证通过
///
/// 对任意由生成器产生的合法类型化函数（SSA 单赋值、操作数类型合法、每块恰一个
/// 合法终结指令、跳转目标存在），`validate_ir` 恒返回 `Ok`。
///
/// **Validates: Requirements 7.2**
test "Feature: production-hardening, Property 7: legal SSA validates Ok" {
  let ok = @infra_pbt.holds_for_all(
    gen_legal_function(),
    pbt_legal_validates,
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 7: 重复定义触发 SsaViolation
///
/// 对任意「同一寄存器被定义两次」的函数，`validate_ir` 返回 `Err` 且诊断列表
/// 含对应寄存器的 `SsaViolation`。
///
/// **Validates: Requirements 7.3**
test "Feature: production-hardening, Property 7: duplicate def yields SsaViolation" {
  let ok = @infra_pbt.holds_for_all(
    gen_dup_def(),
    pbt_has_ssa_violation,
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 7: 类型不符触发 TypeMismatch
///
/// 对任意含单处操作数类型违规的函数，`validate_ir` 返回 `Err` 且诊断列表含
/// `TypeMismatch`。
///
/// **Validates: Requirements 7.4**
test "Feature: production-hardening, Property 7: type violation yields TypeMismatch" {
  let ok = @infra_pbt.holds_for_all(
    gen_type_violation(),
    pbt_has_type_mismatch,
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 7: 控制流缺失触发 ControlFlowError
///
/// 对任意「跳到不存在块」或「缺失终结指令」的函数，`validate_ir` 返回 `Err`
/// 且诊断列表含 `ControlFlowError`。
///
/// **Validates: Requirements 7.5**
test "Feature: production-hardening, Property 7: control-flow gap yields ControlFlowError" {
  let ok = @infra_pbt.holds_for_all(
    gen_cfg_violation(),
    pbt_has_control_flow_error,
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 7: 解释器对相同输入求值确定
///
/// 对任意合法函数与任意入参 Map，`interp_ir` 两次求值结果完全相等（确定性）。
///
/// **Validates: Requirements 7.6**
test "Feature: production-hardening, Property 7: interpreter is deterministic" {
  let ok = @infra_pbt.holds_for_all(
    gen_legal_function_with_args(),
    pbt_interp_deterministic,
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 7: 直线 add 解释结果等于手算期望
///
/// 对任意整数对 `(a, b)`，函数 `r1 = Imm(a) + Imm(b); ret r1` 的解释返回值
/// 恒为 `Some(a + b)`（解释器算术语义正确，AC6 的具体例证）。
///
/// **Validates: Requirements 7.6**
test "Feature: production-hardening, Property 7: straight-line add evaluates to a+b" {
  let ok = @infra_pbt.holds_for_all(
    gen_add_case(),
    pbt_add_interp_correct,
    iters=100,
  )
  assert_true(ok)
}
