// compiler_ext_prop_wbtest.mbt —— 编译器增强属性测试（任务 10.3，白盒）。
//
// 设计依据（design.md §「正确性属性」Property 9，Requirement 9.2/9.3/9.4/9.5）：
//   Property 9（R9 优化等价与 TCO）—— peephole/TCO 优化前后求值结果相等；深度 N
//   尾递归帧数不随 N 线性增长；类型错误同含 expected 与 actual。
//
// 本文件系统化覆盖 Property 9 的四条子属性（每条 `iters >= 100`、三后端一致）：
//   属性 1（AC4）：优化前后求值相等 —— 随机生成**合法且良类型**源程序，编译为
//     `Bytecode`，断言 `VM::run(peephole_opt(bc)) == VM::run(bc)` 且
//     `run_tco(tco_opt(bc)) == VM::run(bc)`。
//   属性 2（AC2）：peephole 指令数不增 —— 随机程序，断言
//     `peephole_opt(bc).instrs.length() <= bc.instrs.length()`。
//   属性 3（AC3）：TCO 帧数不随 N 线性增长 —— 尾递归 countdown 程序对随机的不同
//     N 测最大活动帧深，断言两者相等（与 N 无关的常数）。
//   属性 4（AC5）：类型错误含 expected/actual —— 随机构造类型不一致的 `ExprX`
//     （列表元素类型冲突 / match 各 arm 类型冲突 / 模式与 scrutinee 类型不兼容），
//     断言 `check_x` 返回 `Err(TypeMismatch)` 且 `expected != actual`。
//
// 置于白盒测试（`*_wbtest.mbt`，与被测代码同包）的原因：属性 4 需在包内直接构造
// 扩展语法树 `ExprX` / `Pattern` 与既有 `Expr` 构造子，并断言 `TypeMismatch` 的
// `expected` / `actual` 字段（`TyX` 派生 `Eq`）；属性 1~3 直接消费包内 `Bytecode`
// / `Instr` 结构。与任务 10.1/10.2 的白盒烟雾测试同包共存，本文件为旁路新增测试，
// 不修改任何既有源文件与签名。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（白盒测试期
// 依赖 `for "wbtest"`）；每条属性显式传入 `iters=pbt_prop9_iters`（=100）。
//
// 旁路新增 / 既有 API（本文件只调用、不修改）：
//   peephole_opt / tco_opt / run_tco / run_tco_with_depth（peephole.mbt / tco.mbt）
//   check_x（match_ext.mbt）；既有 compile_ml / VM::run / ml_env_empty /
//   lex_ml / parse_ml / infer（只读复用）。
//
// 反模式禁令（遵循 quality-enforcement / anti-patterns 约束）：
//   * 无循环内字符串 `+` —— 源程序文本一律用 `Array[String]` + `join("")` 物化；
//   * 无 `abort()` / `todo!()` / `panic` 占位 —— 谓词对任意输入均返回 `Bool`
//     （编译失败的退化输入返回 `false`，使反例如实暴露）；
//   * 无 magic number —— 生成器规模与取值范围以命名常量表达；
//   * 断言统一以 `assert_true` + 派生 `Eq` / `match` 表达。

// ───────────────────────────── 规模 / 取值常量 ─────────────────────────────

///|
/// 每条 Property 9 属性的迭代次数（满足「每条属性测试 ≥100 迭代」基线）。
let pbt_prop9_iters : Int = 100

///|
/// 随机整数常量的取值下界（源程序字面量），刻意保持较小以便阅读与稳定。
let pbt_int_lo : Int = 0

///|
/// 随机整数常量的取值上界（源程序字面量）。
let pbt_int_hi : Int = 40

///|
/// 阶乘类递归程序的输入上界（`f k`，`k ∈ [0, pbt_fact_hi]`）；保持较小避免无谓的
/// 大数运算（等价性与溢出无关：两路求值同样回绕）。
let pbt_fact_hi : Int = 8

///|
/// 尾递归 countdown 程序的输入下界（`f N`，N ∈ [pbt_tco_n_lo, pbt_tco_n_hi]）。
let pbt_tco_n_lo : Int = 10

///|
/// 尾递归 countdown 程序的输入上界。经 TCO 后活动帧深恒定，故 N 可取较大值而不致
/// 帧堆积；属性 3 据此断言不同 N 的最大帧深相等（与 N 无关）。
let pbt_tco_n_hi : Int = 300

///|
/// `gen_program` 的源程序模板种类数（见 `build_program` 的分支）。
let pbt_program_kinds : Int = 9

///|
/// `gen_ill_typed` 的类型错误构造种类数（见 `build_ill_typed` 的分支）。
let pbt_ill_typed_kinds : Int = 4

///|
/// 列表元素类型冲突样例中，冲突布尔元素之前的整数前缀元素个数上界。
let pbt_list_prefix_hi : Int = 3

///|
/// 属性测试统一占位位置（行列对求值 / 类型检查均无影响）。
fn px_sp() -> Span {
  Span::{ line: 1, col: 1 }
}

// ───────────────────────────── 源程序生成（合法 + 良类型） ─────────────────────────────

///|
/// 采样一个落在 `[pbt_int_lo, pbt_int_hi]` 的整数字面量文本。
fn px_int(rng : @infra_pbt.Rng) -> String {
  rng.next_range(pbt_int_lo, pbt_int_hi).to_string()
}

///|
/// 依据随机种类构造**确定可编译且良类型**的 MiniML 源程序文本（求值结果均为
/// `VInt` / `VBool`，故 `VM::run` 的 `Val` 比较有意义，且不含闭包不便比较的结果）。
/// 全程以 `Array[String]` + `join("")` 物化，杜绝循环内字符串 `+`。
fn build_program(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(pbt_program_kinds) {
    // 0：整数算术（加 / 乘混合，结果 int）。
    0 => [px_int(rng), " + ", px_int(rng), " * ", px_int(rng)].join("")
    // 1：整数算术（减 / 加，结果 int）。
    1 => [px_int(rng), " - ", px_int(rng), " + ", px_int(rng)].join("")
    // 2：比较（结果 bool）。
    2 => [px_int(rng), " < ", px_int(rng)].join("")
    // 3：if 表达式（两分支均 int，结果 int）。
    3 =>
      [
        "if ",
        px_int(rng),
        " <= ",
        px_int(rng),
        " then ",
        px_int(rng),
        " else ",
        px_int(rng),
      ].join("")
    // 4：let 绑定（结果 int）。
    4 => ["let x = ", px_int(rng), " in x + ", px_int(rng)].join("")
    // 5：lambda 应用（结果 int）。
    5 => ["(fun x -> x + ", px_int(rng), ") ", px_int(rng)].join("")
    // 6：高阶函数（twice/inc 组合，结果 int）。
    6 =>
      [
        "let twice = fun f -> fun x -> f (f x) in let inc = fun n -> n + ",
        px_int(rng),
        " in twice inc ",
        px_int(rng),
      ].join("")
    // 7：尾递归 countdown（尾位置调用，结果 int = 基准值）。
    7 =>
      [
        "let rec f = fun n -> if n <= 0 then ",
        px_int(rng),
        " else f (n - 1) in f ",
        rng.next_range(pbt_int_lo, pbt_int_hi).to_string(),
      ].join("")
    // 8：阶乘类递归（非尾递归，结果 int）。
    _ =>
      [
        "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f ",
        rng.next_range(0, pbt_fact_hi).to_string(),
      ].join("")
  }
}

///|
/// 合法且良类型源程序生成器（属性 1 / 属性 2 复用）。
fn gen_program() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) { build_program(rng) })
}

///|
/// 尾递归 countdown 源程序文本：`let rec f = fun n -> if n <= 0 then 0 else
/// f (n - 1) in f N`，其尾调用 `f (n - 1)` 处于尾位置（属性 3 复用）。
fn countdown_program(n : Int) -> String {
  ["let rec f = fun n -> if n <= 0 then 0 else f (n - 1) in f ", n.to_string()].join(
    "",
  )
}

///|
/// 尾递归 N 值对生成器（属性 3 复用）：两个独立的 N（均落在 [lo, hi]），用于断言
/// 不同 N 下经 TCO 的最大活动帧深相等（与 N 无关的常数）。
fn gen_tco_pair() -> @infra_pbt.Gen[(Int, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let a = rng.next_range(pbt_tco_n_lo, pbt_tco_n_hi)
    let b = rng.next_range(pbt_tco_n_lo, pbt_tco_n_hi)
    (a, b)
  })
}

// ───────────────────────────── 类型不一致 ExprX 生成 ─────────────────────────────

///|
/// 依据随机种类构造**类型不一致**的扩展表达式 `ExprX`，使 `check_x` 必返回
/// `Err(TypeMismatch)` 且 `expected != actual`：
///   0：列表元素类型冲突 `[i0, i1, ..., bool]`（expected=TXInt、actual=TXBool）；
///   1：match 各 arm body 类型冲突（首 arm 返回 int、次 arm 返回 bool）；
///   2：元组模式匹配整数 scrutinee（expected=TXInt、actual=TXTuple([...])）；
///   3：布尔字面量模式匹配整数 scrutinee（expected=TXInt、actual=TXBool）。
fn build_ill_typed(rng : @infra_pbt.Rng) -> ExprX {
  match rng.next_below(pbt_ill_typed_kinds) {
    // 0：列表元素类型冲突——若干 int 前缀后接一个 bool。
    0 => {
      let elems : Array[ExprX] = []
      let prefix = rng.next_range(1, pbt_list_prefix_hi)
      let mut i = 0
      while i < prefix {
        elems.push(XBase(EInt(rng.next_range(pbt_int_lo, pbt_int_hi), px_sp())))
        i = i + 1
      }
      elems.push(XBase(EBool(rng.next_bool(), px_sp())))
      XList(elems, px_sp())
    }
    // 1：match 各 arm body 类型冲突——scrutinee 为 int，arm1→int、arm2→bool。
    1 =>
      XMatch(
        XBase(EInt(rng.next_range(pbt_int_lo, pbt_int_hi), px_sp())),
        [
          (PWild, XBase(EInt(rng.next_range(pbt_int_lo, pbt_int_hi), px_sp()))),
          (PVar("v"), XBase(EBool(rng.next_bool(), px_sp()))),
        ],
        px_sp(),
      )
    // 2：元组模式匹配整数 scrutinee。
    2 =>
      XMatch(
        XBase(EInt(rng.next_range(pbt_int_lo, pbt_int_hi), px_sp())),
        [
          (
            PTuple([PVar("a"), PVar("b")]),
            XBase(EInt(rng.next_range(pbt_int_lo, pbt_int_hi), px_sp())),
          ),
        ],
        px_sp(),
      )
    // 3：布尔字面量模式匹配整数 scrutinee。
    _ =>
      XMatch(
        XBase(EInt(rng.next_range(pbt_int_lo, pbt_int_hi), px_sp())),
        [(PBool(rng.next_bool()), XBase(EInt(0, px_sp())))],
        px_sp(),
      )
  }
}

///|
/// 类型不一致 `ExprX` 生成器（属性 4 复用）。
fn gen_ill_typed() -> @infra_pbt.Gen[ExprX] {
  @infra_pbt.Gen::new(fn(rng) { build_ill_typed(rng) })
}

// ───────────────────────────── 编译夹具与谓词 ─────────────────────────────

///|
/// 源程序文本 → 词法 → 语法 → 推断 → 字节码；任一阶段失败返回 `None`（使退化输入
/// 在谓词中如实暴露为反例，而非 `abort`）。生成器仅产出合法程序，正常恒为 `Some`。
fn px_compile(src : String) -> Bytecode? {
  match lex_ml(src) {
    Ok(tokens) =>
      match parse_ml(tokens) {
        Ok(e) =>
          match infer(e) {
            Ok((te, _)) => Some(compile_ml(te))
            Err(_) => None
          }
        Err(_) => None
      }
    Err(_) => None
  }
}

///|
/// 谓词（属性 1 / AC4）：对编译所得字节码 `bc`，
/// `VM::run(peephole_opt(bc)) == VM::run(bc)` 且 `run_tco(tco_opt(bc)) == VM::run(bc)`。
fn pbt_opt_preserves_eval(src : String) -> Bool {
  match px_compile(src) {
    None => false
    Some(bc) => {
      let base = VM::run(bc, ml_env_empty())
      let ph = VM::run(peephole_opt(bc), ml_env_empty())
      let tco = run_tco(tco_opt(bc), ml_env_empty())
      base == ph && base == tco
    }
  }
}

///|
/// 谓词（属性 2 / AC2）：`peephole_opt(bc).instrs.length() <= bc.instrs.length()`。
fn pbt_peephole_not_increasing(src : String) -> Bool {
  match px_compile(src) {
    None => false
    Some(bc) => peephole_opt(bc).instrs.length() <= bc.instrs.length()
  }
}

///|
/// 谓词（属性 3 / AC3）：对两个不同 N 的尾递归 countdown，经 `tco_opt` 规范化后用
/// `run_tco_with_depth` 测最大活动帧深，二者应相等（与 N 无关的常数），且结果均为
/// `VInt(0)`、帧深为远小于 N 的小常数（不随 N 线性增长）。编译失败返回 `false`。
fn pbt_tco_depth_constant(ns : (Int, Int)) -> Bool {
  let (n1, n2) = ns
  match (px_compile(countdown_program(n1)), px_compile(countdown_program(n2))) {
    (Some(bc1), Some(bc2)) => {
      let (r1, d1) = run_tco_with_depth(tco_opt(bc1), ml_env_empty())
      let (r2, d2) = run_tco_with_depth(tco_opt(bc2), ml_env_empty())
      // 结果正确（均为 0）、帧深与 N 无关（相等）、且为远小于 N 的小常数。
      r1 == VInt(0) && r2 == VInt(0) && d1 == d2 && d1 < pbt_tco_n_lo
    }
    _ => false
  }
}

///|
/// 谓词（属性 4 / AC5）：类型不一致 `ExprX` 经 `check_x` 返回 `Err(TypeMismatch)`
/// 且 `expected != actual`（两个字段确被填充为不同类型，反映期望与实际类型）。
fn pbt_type_error_has_expected_actual(ex : ExprX) -> Bool {
  match check_x(ex) {
    Ok(_) => false
    Err(tm) => tm.expected != tm.actual
  }
}

// ───────────────────────────── 属性测试 ─────────────────────────────

///|
/// Feature: production-hardening, Property 9: 优化前后求值相等
///
/// 对任意随机生成的合法且良类型源程序，编译为字节码后，peephole 优化与 TCO 优化
/// （`run_tco(tco_opt(bc))`）的求值结果均与未优化的 `VM::run(bc)` 逐位相等。
///
/// **Validates: Requirements 9.4**
test "Feature: production-hardening, Property 9: optimization preserves evaluation" {
  let ok = @infra_pbt.holds_for_all(
    gen_program(),
    pbt_opt_preserves_eval,
    iters=pbt_prop9_iters,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 9: peephole 指令数不增
///
/// 对任意随机生成的合法源程序，`peephole_opt` 产出的字节码指令数不超过原字节码
/// 指令数。
///
/// **Validates: Requirements 9.2**
test "Feature: production-hardening, Property 9: peephole does not increase instruction count" {
  let ok = @infra_pbt.holds_for_all(
    gen_program(),
    pbt_peephole_not_increasing,
    iters=pbt_prop9_iters,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 9: TCO 帧数不随 N 线性增长
///
/// 对尾递归 countdown 程序的任意两个不同输入 N，经 TCO 执行测得的最大活动帧深
/// 相等（与 N 无关的小常数），佐证帧数不随递归深度 N 线性增长。
///
/// **Validates: Requirements 9.3**
test "Feature: production-hardening, Property 9: TCO frame depth independent of N" {
  let ok = @infra_pbt.holds_for_all(
    gen_tco_pair(),
    pbt_tco_depth_constant,
    iters=pbt_prop9_iters,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 9: 类型错误同含 expected 与 actual
///
/// 对任意随机构造的类型不一致 `ExprX`（列表元素类型冲突 / match arm 类型冲突 /
/// 模式与 scrutinee 类型不兼容），`check_x` 返回 `Err(TypeMismatch)`，且其
/// `expected` 与 `actual` 两字段均被填充为彼此不同的类型。
///
/// **Validates: Requirements 9.5**
test "Feature: production-hardening, Property 9: type mismatch carries expected and actual" {
  let ok = @infra_pbt.holds_for_all(
    gen_ill_typed(),
    pbt_type_error_has_expected_actual,
    iters=pbt_prop9_iters,
  )
  assert_true(ok)
}
