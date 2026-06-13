// prop_error_test.mbt —— Mini_Compiler 词法/语法错误条件属性测试（task 15.4）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 2：「Mini_Compiler 词法/语法错误条件」——对任意注入了词法或语法
// 错误的源码字符串，编译器应返回包含错误类别与行列位置的诊断，且不产生 AST：
//
//   * 词法非法（含字母表之外的字符，如 @ # ; 等）→ `lex` 返回
//     `Err(Diagnostic { kind: LexError, line, col, .. })`，且 line/col 合理；
//   * 语法非法（运算符后缺操作数、未闭合括号、多余 ) 等，但词法合法）→
//     `lex` 成功，`parse(lex(...))` 返回
//     `Err(Diagnostic { kind: SyntaxError, line, col, .. })`，且 line/col 合理；
//   * 两类情形均**只**返回含类别与位置的诊断，绝不产生 AST（`Ok(_)` 即判失败）。
//
// 复用共享 PBT 包 @infra_pbt 的种子驱动随机源 `Rng`、生成器 `Gen` 与不变量
// 断言模板 `holds_for_all`（默认迭代 100 次，满足 Requirement 11.3 的 ≥100
// 迭代基线），并保证 wasm-gc / js / native 三后端逐位一致与可重放。
//
// 生成器设计要点（保证落在「确定非法」的输入空间内）：
//   * 词法非法：取一个合法 token 前缀（整数或标识符）+ 一枚字母表之外的非法
//     字符（@ # ; $ % & ! ? ~ ^）+ 合法后缀。`lex` 自左向右扫描，必在该非法
//     字符处返回 `LexError`（前缀全为合法字符，不会提前出错）。
//   * 语法非法：仅由合法词法字符（数字 / 字母 / 空白 / `+ - * / ( ) =` /
//     关键字）构成，故 `lex` 必成功；其结构经文法分析必失败：
//       - 尾随运算符：`<atom> <op>`（运算符后缺操作数）；
//       - 前导运算符：`<op> <atom>`（表达式起始处非原子）；
//       - 未闭合括号：`( <atom>`（缺 `)`）；
//       - 多余右括号：`<atom> )`（顶层残留输入）；
//       - 双运算符：`<atom> <op> <op> <atom>`（中缺操作数）；
//       - 残缺 let：`let <ident>`（缺 `=` 与 `in` 子句）。
//     以上六类无论 atom/op 如何采样均确定性地触发 `SyntaxError`。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 采样基元（sampling primitives）—— 合法 atom / 运算符 / 非法字符
// ---------------------------------------------------------------------------

///|
/// 供错误条件测试采样的合法标识符池（均非关键字 `let` / `in`）。
///
/// 命名以 `err_` 前缀，避免与 prop_roundtrip_test.mbt 中的同包符号冲突。
let err_ident_pool : Array[String] = ["a", "b", "x", "y", "foo", "bar"]

///|
/// 采样一个「合法 atom」源串：非负整数字面量或合法标识符。
///
/// 二者都恰好词法成功并解析为单个原子表达式，作为构造错误样例的合法骨架。
fn gen_err_atom(rng : @infra_pbt.Rng) -> String {
  if rng.next_bool() {
    rng.next_range(0, 9999).to_string()
  } else {
    err_ident_pool[rng.next_below(err_ident_pool.length())]
  }
}

///|
/// 采样一个二元算术运算符的词素文本（`+` / `-` / `*` / `/`）。
fn gen_err_op(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(4) {
    0 => "+"
    1 => "-"
    2 => "*"
    _ => "/"
  }
}

///|
/// 字母表之外的非法字符池（MiniLet 既非空白 / 数字 / 字母 / `_`，也非
/// `+ - * / ( ) =` 的字符），任一出现都会使 `lex` 返回 `LexError`。
let illegal_chars : Array[Char] = [
  '@', '#', ';', '$', '%', '&', '!', '?', '~', '^',
]

// ---------------------------------------------------------------------------
// 错误源串生成器（generators）
// ---------------------------------------------------------------------------

///|
/// 生成「确定词法非法」的源串：合法前缀 + 字母表外非法字符 + 合法后缀。
///
/// `lex` 自左向右扫描，前缀全为合法字符不会出错，必在非法字符处返回
/// `LexError`，因此该串确定性地触发词法诊断。
fn gen_lex_illegal(rng : @infra_pbt.Rng) -> String {
  let prefix = gen_err_atom(rng)
  let bad = illegal_chars[rng.next_below(illegal_chars.length())]
  prefix + " " + bad.to_string() + " 1"
}

///|
/// 生成「词法合法但语法非法」的源串：六类确定性触发 `SyntaxError` 的结构。
///
/// 全部仅由合法词法字符构成，故 `lex` 必成功；结构缺陷使递归下降解析必失败。
fn gen_syntax_illegal(rng : @infra_pbt.Rng) -> String {
  let atom = gen_err_atom(rng)
  match rng.next_below(6) {
    // 尾随运算符：运算符后缺操作数，如 "5 +"。
    0 => atom + " " + gen_err_op(rng)
    // 前导运算符：表达式起始处即为运算符，如 "* 5"。
    1 => gen_err_op(rng) + " " + atom
    // 未闭合括号：缺右括号，如 "( 5"。
    2 => "( " + atom
    // 多余右括号：顶层解析后残留 ")"，如 "5 )"。
    3 => atom + " )"
    // 双运算符：两运算符之间缺操作数，如 "5 + * 5"。
    4 => atom + " " + gen_err_op(rng) + " " + gen_err_op(rng) + " " + atom
    // 残缺 let：缺 "=" 与 "in" 子句，如 "let x"。
    _ => "let " + err_ident_pool[rng.next_below(err_ident_pool.length())]
  }
}

///|
/// 错误源串生成器：随机产出（源串，期望诊断类别）二元组。
///
/// 期望类别用 `DiagKind`（同包 pub(all)）携带，使谓词据此精确断言诊断类别。
fn gen_illegal_source() -> @infra_pbt.Gen[(String, DiagKind)] {
  @infra_pbt.Gen::new(fn(rng) {
    if rng.next_bool() {
      (gen_lex_illegal(rng), LexError)
    } else {
      (gen_syntax_illegal(rng), SyntaxError)
    }
  })
}

// ---------------------------------------------------------------------------
// 性质谓词（property predicate）
// ---------------------------------------------------------------------------

///|
/// Property 2 的核心谓词：注入错误的源串必产出含类别与位置的诊断、不产生 AST。
///
///   * 期望 `LexError`：`lex` 返回 `Err`，其 `kind == LexError` 且行列 ≥ 1；
///     若 `lex` 反而成功（`Ok`）则判失败。
///   * 期望 `SyntaxError`：`lex` 必须成功（词法合法），随后 `parse` 返回 `Err`，
///     其 `kind == SyntaxError` 且行列 ≥ 1；若 `parse` 产出了 `Ok(ast)`（即产生
///     了 AST）则判失败。
fn illegal_source_diagnoses(pair : (String, DiagKind)) -> Bool {
  let (src, expected) = pair
  match expected {
    LexError =>
      match lex(src) {
        Err(d) => d.kind == LexError && d.line >= 1 && d.col >= 1
        Ok(_) => false // 词法非法却产出 token 流 —— 性质被违反
      }
    SyntaxError =>
      match lex(src) {
        // 语法样例必须词法合法；若此处出错则生成器约束被破坏。
        Err(_) => false
        Ok(tokens) =>
          match parse(tokens) {
            Err(d) => d.kind == SyntaxError && d.line >= 1 && d.col >= 1
            Ok(_) => false // 语法非法却产生了 AST —— 性质被违反
          }
      }
    // 本属性不生成类型错误样例。
    TypeError => false
  }
}

// ---------------------------------------------------------------------------
// 单元测试（示例 / 边界）—— 锁定各错误类别的具体见证
// ---------------------------------------------------------------------------

///|
/// 词法非法具体见证：非法字符处返回带位置的 `LexError`，不产生 token 流。
test "lexically illegal sources yield a positioned LexError" {
  let samples : Array[String] = ["1 @ 2", "foo # bar", "x ; y", "3 $ 4"]
  for s in samples {
    match lex(s) {
      Err(d) => {
        assert_true(d.kind == LexError)
        assert_true(d.line >= 1 && d.col >= 1)
      }
      Ok(_) => fail("期望词法错误，却成功切分: \{s}")
    }
  }
}

///|
/// 语法非法具体见证：词法成功但语法分析返回带位置的 `SyntaxError`，无 AST。
test "syntactically illegal sources yield a positioned SyntaxError and no AST" {
  let samples : Array[String] = ["5 +", "* 5", "( 5", "5 )", "1 + * 2", "let x"]
  for s in samples {
    match lex(s) {
      Ok(tokens) =>
        match parse(tokens) {
          Err(d) => {
            assert_true(d.kind == SyntaxError)
            assert_true(d.line >= 1 && d.col >= 1)
          }
          Ok(_) => fail("期望语法错误，却产生了 AST: \{s}")
        }
      Err(_) => fail("语法样例应当词法合法: \{s}")
    }
  }
}

// ---------------------------------------------------------------------------
// Property 2：Mini_Compiler 词法/语法错误条件
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 2: Mini_Compiler 词法/语法错误条件
///
/// 对任意由生成器产出的、注入了词法或语法错误的源码字符串，编译器应返回包含
/// 错误类别（`LexError` / `SyntaxError`）与行列位置（line/col ≥ 1）的诊断，且
/// 不产生 AST。复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次
/// （满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 1.3**
test "Feature: moonbit-infra-suite, Property 2: illegal sources yield a positioned diagnostic and no AST" {
  let ok = @infra_pbt.holds_for_all(
    gen_illegal_source(),
    illegal_source_diagnoses,
  )
  assert_true(ok)
}
