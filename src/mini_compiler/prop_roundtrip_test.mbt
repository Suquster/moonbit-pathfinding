// prop_roundtrip_test.mbt —— Mini_Compiler AST 往返属性测试（task 15.3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 1：「Mini_Compiler AST 往返」——对生成器产出的任一合法 AST `a`，
// 将其打印再经词法 / 语法分析重建应还原等价 AST：
//
//     parse(lex(print_ast(a))) ≡ Ok(a)
//
// 复用共享 PBT 包 @infra_pbt 的种子驱动随机源 `Rng`、生成器 `Gen` 与断言
// 模板（`round_trip` 经 `Bytes` 桥接的往返模板，以及 `holds_for_all` 直接
// 谓词模板），二者均以默认 100 次迭代运行（满足 Requirement 11.3 的 ≥100
// 迭代基线），并保证 wasm-gc / js / native 三后端逐位一致与可重放。
//
// 生成器设计要点（保证落在「可往返」的输入空间内）：
//   * 整数字面量取非负值——`print_ast` 直接输出十进制串，负号会被词法切成
//     `Minus` 与整数两枚词法单元而破坏往返，故约束为 [0, 9999]。
//   * 标识符取自固定的合法标识符池（ALPHA (ALPHA|DIGIT|_)*，且排除关键字
//     `let` / `in`），与文法的 IDENT 终结符一致。
//   * `print_ast` 对二元运算节点**完全括号化**（`( lhs op rhs )`），使其与
//     运算符优先级 / 结合性无关地往返；但 `Let` 节点按文法形态打印且**不**
//     额外加括号，其 body 在重新解析时会贪婪延伸。因此生成器约束：`Bin` 的
//     两个操作数只能是「非顶层 let」表达式（叶子或嵌套 `Bin`），`Let` 仅出现
//     在顶层、或作为另一 `Let` 的 bound / body——这些位置上 `let ... in ...`
//     的边界由文法唯一确定，往返无歧义。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 合法标识符池（valid identifier pool）
// ---------------------------------------------------------------------------

///|
/// 供 `Var` / `Let` 绑定名采样的合法标识符集合。
///
/// 每个名字均满足文法 IDENT ::= ALPHA (ALPHA | DIGIT | '_')*，且均非关键字
/// （`let` / `in`），故经 `print_ast` 输出后必然被词法器识别为 `Ident`。
let ident_pool : Array[String] = [
  "a", "b", "c", "x", "y", "z", "foo", "bar", "baz", "n", "m", "k",
]

///|
/// 从标识符池随机取一个合法标识符。
fn gen_ident(rng : @infra_pbt.Rng) -> String {
  ident_pool[rng.next_below(ident_pool.length())]
}

///|
/// 随机二元算术运算符。
fn gen_binop(rng : @infra_pbt.Rng) -> BinOp {
  match rng.next_below(4) {
    0 => Add
    1 => Sub
    2 => Mul
    _ => Div
  }
}

///|
/// 随机叶子节点：非负整数字面量或变量引用。
fn gen_leaf(rng : @infra_pbt.Rng) -> Ast {
  if rng.next_bool() {
    Int(rng.next_range(0, 9999))
  } else {
    Var(gen_ident(rng))
  }
}

// ---------------------------------------------------------------------------
// AST 生成器（generator）—— 深度受限的随机合法 Ast
// ---------------------------------------------------------------------------

///|
/// 合法 AST 生成器：深度受限的随机 MiniLet 表达式（顶层允许 `Let`）。
fn gen_ast() -> @infra_pbt.Gen[Ast] {
  @infra_pbt.Gen::new(fn(rng) { gen_expr_at(rng, 4) })
}

///|
/// 在给定剩余深度下采样任意表达式：叶子 / `Bin`（操作数受限）/ `Let`。
///
/// `Bin` 的子节点改用 `gen_operand_at` 采样，以排除「未括号化的顶层 let」作为
/// 操作数（否则重新解析时 let 的 body 会贪婪吞并运算符，破坏往返）。`Let` 的
/// bound 与 body 可为任意表达式（含嵌套 `Let`），其边界由文法唯一确定。
fn gen_expr_at(rng : @infra_pbt.Rng, depth : Int) -> Ast {
  if depth <= 0 {
    gen_leaf(rng)
  } else {
    match rng.next_below(4) {
      0 => gen_leaf(rng)
      1 =>
        Bin(
          gen_binop(rng),
          gen_operand_at(rng, depth - 1),
          gen_operand_at(rng, depth - 1),
        )
      _ =>
        Let(
          gen_ident(rng),
          gen_expr_at(rng, depth - 1),
          gen_expr_at(rng, depth - 1),
        )
    }
  }
}

///|
/// 操作数表达式采样：仅叶子或嵌套 `Bin`，绝不产生顶层 `Let`。
///
/// 保证作为 `Bin` 直接子节点时，`print_ast` 的完全括号化输出可被无歧义地
/// 解析回同一结构。
fn gen_operand_at(rng : @infra_pbt.Rng, depth : Int) -> Ast {
  if depth <= 0 || rng.next_below(2) == 0 {
    gen_leaf(rng)
  } else {
    Bin(
      gen_binop(rng),
      gen_operand_at(rng, depth - 1),
      gen_operand_at(rng, depth - 1),
    )
  }
}

// ---------------------------------------------------------------------------
// Bytes 编解码桥接（供 round_trip 模板使用）
// ---------------------------------------------------------------------------

///|
/// 编码：AST -> `print_ast` 源串 -> `Bytes`（逐字符取 ASCII 码）。
///
/// `print_ast` 仅输出 ASCII 字符（数字 / 字母 / 空格 / `+ - * / ( ) =`），
/// 故 `to_byte` 无损。
fn ast_to_bytes(a : Ast) -> Bytes {
  let s = print_ast(a)
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 解码：`Bytes` -> 源串 -> `lex` -> `parse` -> AST。
///
/// 与 `ast_to_bytes` 互逆；词法或语法任一阶段失败均返回 `None`（往返失败）。
fn bytes_to_ast(b : Bytes) -> Ast? {
  let mut s = ""
  let mut i = 0
  while i < b.length() {
    let c = b[i].to_int().unsafe_to_char()
    s = s + "\{c}"
    i = i + 1
  }
  match lex(s) {
    Err(_) => None
    Ok(tokens) =>
      match parse(tokens) {
        Err(_) => None
        Ok(a) => Some(a)
      }
  }
}

// ---------------------------------------------------------------------------
// 单元测试（示例 / 边界）—— 锁定生成器约束下的往返具体见证
// ---------------------------------------------------------------------------

///|
/// 含 `Let` 作为 `Bin` 操作数的 AST 不在生成器输出空间内——此例显式见证
/// 「未括号化 let」会破坏往返，从而说明生成器约束的必要性。
test "let as a bin operand is intentionally excluded from the generator" {
  // Bin(Add, Let("x", 1, 2), 3) 打印为 "(let x = 1 in 2 + 3)"，重新解析时
  // let 的 body 会贪婪吞并 "+ 3"，得到 Let("x", 1, Bin(Add, 2, 3))，不等于原树。
  let a : Ast = Bin(Add, Let("x", Int(1), Int(2)), Int(3))
  match lex(print_ast(a)) {
    Ok(tokens) => assert_false(parse(tokens) == Ok(a))
    Err(_) => fail("lex 意外失败")
  }
}

///|
/// 生成器允许的形态（`Bin` 操作数为叶子 / 嵌套 Bin，`Let` 居 bound/body）往返自洽。
test "generator-shaped asts round-trip" {
  let samples : Array[Ast] = [
    Bin(Mul, Bin(Add, Int(1), Var("x")), Int(3)),
    Let("x", Bin(Add, Int(1), Int(2)), Bin(Mul, Var("x"), Int(3))),
    Let("y", Let("z", Int(1), Var("z")), Var("y")),
  ]
  for a in samples {
    match lex(print_ast(a)) {
      Ok(tokens) => assert_true(parse(tokens) == Ok(a))
      Err(_) => fail("lex 意外失败")
    }
  }
}

// ---------------------------------------------------------------------------
// Property 1：Mini_Compiler AST 往返
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 1: Mini_Compiler AST 往返（round_trip 模板）
///
/// 对任意由生成器产出的合法 AST `a`，经「打印 → Bytes → 词法 → 语法」的往返
/// 应还原为等价 AST（`parse(lex(print_ast(a))) ≡ Ok(a)`）。复用 @infra_pbt 的
/// `round_trip` 往返断言模板，默认迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 1.2, 1.8**
test "Feature: moonbit-infra-suite, Property 1: parse(lex(print_ast(a))) round-trips (round_trip template)" {
  let ok = @infra_pbt.round_trip(gen_ast(), ast_to_bytes, bytes_to_ast)
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 1: Mini_Compiler AST 往返（holds_for_all 模板）
///
/// 同一往返性质的直接谓词形式：对任意生成的 AST `a`，
/// `parse(lex(print_ast(a)))` 应恰好等于 `Ok(a)`。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 1.2, 1.8**
test "Feature: moonbit-infra-suite, Property 1: parse(lex(print_ast(a))) equals Ok(a) (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_ast(), fn(a) {
    match lex(print_ast(a)) {
      Ok(tokens) => parse(tokens) == Ok(a)
      Err(_) => false
    }
  })
  assert_true(ok)
}
