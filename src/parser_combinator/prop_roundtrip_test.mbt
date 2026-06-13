// prop_roundtrip_test.mbt —— 解析器组合子语法结构往返属性测试（task 5.4）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 10：「解析器组合子语法结构往返」——对生成器产出的任一合法语法
// 结构 `x`，对其打印再解析应得到等价结构（`parse(print(x)) ≡ x`）。
//
// 为演示并验证该性质，本文件在同包（黑盒测试包）内定义了一个**小型示例
// 语法结构**：完全括号化的算术表达式 AST（`ExampleExpr`），配套：
//   * `print_example_expr` —— 打印器（printer）：把 AST 还原为唯一的、完全
//     括号化的文本形式，从而保证打印结果可被无歧义地解析回来；
//   * `example_expr_parser` —— **基于组合子的解析器**（parser），完全构建于
//     本包的公共原语 / 组合子（`pchar` / `satisfy` / `alt` / `many1`）之上；
//   * `gen_example_expr` —— 深度受限的随机 AST 生成器（复用 @infra_pbt 的
//     种子驱动随机源 `Rng`，保证三后端逐位一致与可重放）。
//
// 往返断言同时以两种模板表达，二者都校验 Property 10：
//   * `@infra_pbt.round_trip`   —— 经 `Bytes` 编解码桥接的往返模板（≥100 迭代）；
//   * `@infra_pbt.holds_for_all` —— 直接以 `parse(print(x)) == Some(x)` 谓词的
//     不变量模板（默认 `iters=100`）。
//
// 示例语法刻意保持完全括号化（fully-parenthesized），使打印形式与解析互为
// 双射，避免运算符优先级带来的歧义——这是"打印再解析得到等价结构"成立的
// 关键前提，也使本属性测试聚焦于组合子地基本身的往返能力（R4.5）。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 示例语法结构（example grammar）：完全括号化算术表达式 AST
// ---------------------------------------------------------------------------

///|
/// 小型示例 AST：完全括号化的算术表达式。
///
/// 文法（grammar）：
///   expr  := number | "(" expr op expr ")"
///   op    := "+" | "*"
///   number:= digit+            （非负整数，无前导符号）
///
/// 选择"完全括号化"是为了让 `print` 与 `parse` 互为双射：每个二元节点都被
/// 一对括号唯一界定，因此不存在优先级/结合性歧义，`parse(print(x)) ≡ x`
/// 对任意合法 AST 恒成立。`derive(Eq)` 供往返等价比较（`round_trip` 要求
/// `T : Eq`）。
enum ExampleExpr {
  Num(Int)
  Add(ExampleExpr, ExampleExpr)
  Mul(ExampleExpr, ExampleExpr)
} derive(Eq)

///|
/// 打印器（printer）：把 AST 还原为唯一的完全括号化文本。
///
///   Num(n)    -> "n"
///   Add(a, b) -> "(" ++ print(a) ++ "+" ++ print(b) ++ ")"
///   Mul(a, b) -> "(" ++ print(a) ++ "*" ++ print(b) ++ ")"
///
/// 产出仅含 ASCII 字符（`0`~`9` / `(` / `)` / `+` / `*`），便于经 `Bytes`
/// 往返而不丢失信息。
fn print_example_expr(e : ExampleExpr) -> String {
  match e {
    Num(n) => "\{n}"
    Add(a, b) => "(" + print_example_expr(a) + "+" + print_example_expr(b) + ")"
    Mul(a, b) => "(" + print_example_expr(a) + "*" + print_example_expr(b) + ")"
  }
}

// ---------------------------------------------------------------------------
// 基于组合子的解析器（combinator-based parser）
// ---------------------------------------------------------------------------

// 实现说明：示例解析器以「消费 `Input` 返回 `(产出, 剩余输入)?`」的惰性
// 递归下降（recursive descent）形式组合本包的公共原语 / 组合子（`pchar` /
// `satisfy` / `many1` / `alt`）。字符级匹配完全交由这些组合子完成，递归函数
// 仅负责**对组合子结果做模式匹配并按序串联**；`ParseResult` 的构造留在包内
// （其变体对外只读），故此处不构造 `ParseResult`，只消费它。

///|
/// 数字字符原语：匹配单个十进制数字（基于 `satisfy` 组合子）。
fn example_digit() -> Parser[Char] {
  satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
}

///|
/// 数字字面量产生式：`digit+` -> `Num`。
///
/// 复用 `many1` 组合子收集一个或多个数字字符，再折叠为整数；失败返回 `None`。
fn parse_num_at(input : Input) -> (ExampleExpr, Input)? {
  match many1(example_digit()).parse(input) {
    Ok(chars, rest) => {
      let mut n = 0
      for c in chars {
        n = n * 10 + (c.to_int() - '0'.to_int())
      }
      Some((ExampleExpr::Num(n), rest))
    }
    Fail(_, ..) => None
  }
}

///|
/// 括号化二元表达式产生式：`"(" expr op expr ")"`。
///
/// 依次消费左括号、左子表达式、运算符（`alt([pchar('+'), pchar('*')])`）、
/// 右子表达式与右括号；任一环节失败即返回 `None`。对 `expr` 的递归引用直接
/// 调用 `parse_expr_at`，由输入推进保证终止。
fn parse_paren_at(input : Input) -> (ExampleExpr, Input)? {
  let r1 = match pchar('(').parse(input) {
    Ok(_, r) => r
    Fail(_, ..) => return None
  }
  let (left, r2) = match parse_expr_at(r1) {
    Some(x) => x
    None => return None
  }
  let (op, r3) = match alt([pchar('+'), pchar('*')]).parse(r2) {
    Ok(op, r) => (op, r)
    Fail(_, ..) => return None
  }
  let (right, r4) = match parse_expr_at(r3) {
    Some(x) => x
    None => return None
  }
  let r5 = match pchar(')').parse(r4) {
    Ok(_, r) => r
    Fail(_, ..) => return None
  }
  let node = if op == '+' {
    ExampleExpr::Add(left, right)
  } else {
    ExampleExpr::Mul(left, right)
  }
  Some((node, r5))
}

///|
/// 表达式产生式：`number | "(" expr op expr ")"`。
///
/// 先尝试数字分支，失败则从**同一起始 `Input`**（不可变游标天然回溯，R4.4）
/// 尝试括号分支。
fn parse_expr_at(input : Input) -> (ExampleExpr, Input)? {
  match parse_num_at(input) {
    Some(r) => Some(r)
    None => parse_paren_at(input)
  }
}

///|
/// 顶层解析入口：解析整段输入并要求**完整消费**至输入末尾。
///
/// 仅当解析成功且剩余输入抵达 EOF 时返回 `Some(ast)`；否则（解析失败或有
/// 尾随未消费字符）返回 `None`。EOF 校验保证 `print` 的双射逆向严格成立，
/// 是 `parse(print(x)) ≡ x` 往返性质的必要条件。
fn parse_example_expr(source : String) -> ExampleExpr? {
  match parse_expr_at(Input::from_string(source)) {
    Some((e, rest)) => if rest.is_eof() { Some(e) } else { None }
    None => None
  }
}

// ---------------------------------------------------------------------------
// AST 生成器（generator）—— 复用 @infra_pbt 种子驱动随机源
// ---------------------------------------------------------------------------

///|
/// 合法示例 AST 生成器：深度受限的随机算术表达式。
fn gen_example_expr() -> @infra_pbt.Gen[ExampleExpr] {
  @infra_pbt.Gen::new(fn(rng) { gen_example_expr_at(rng, 4) })
}

///|
/// 在给定剩余深度下采样一棵 AST。
///
/// 深度耗尽或以 1/3 概率提前收敛为叶子（`Num`，取值 `[0, 999]`），否则递归
/// 生成左右子树并随机选择 `Add` / `Mul`。深度上限保证树规模有界，避免巨树
/// 拖慢 100 次迭代。
fn gen_example_expr_at(rng : @infra_pbt.Rng, depth : Int) -> ExampleExpr {
  if depth <= 0 || rng.next_below(3) == 0 {
    ExampleExpr::Num(rng.next_range(0, 999))
  } else {
    let left = gen_example_expr_at(rng, depth - 1)
    let right = gen_example_expr_at(rng, depth - 1)
    if rng.next_bool() {
      ExampleExpr::Add(left, right)
    } else {
      ExampleExpr::Mul(left, right)
    }
  }
}

// ---------------------------------------------------------------------------
// Bytes 编解码桥接（供 round_trip 模板使用）
// ---------------------------------------------------------------------------

///|
/// 编码：AST -> 打印文本 -> `Bytes`（逐字符取 ASCII 码）。
///
/// 打印结果仅含 ASCII 字符（码位 < 128），故 `to_byte` 无损。
fn expr_to_bytes(e : ExampleExpr) -> Bytes {
  let s = print_example_expr(e)
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 解码：`Bytes` -> 文本（逐字节还原 ASCII 字符）-> 解析为 AST。
///
/// 与 `expr_to_bytes` 互逆；解析失败时返回 `None`（往返失败）。
fn bytes_to_expr(b : Bytes) -> ExampleExpr? {
  let mut s = ""
  let mut i = 0
  while i < b.length() {
    let c = b[i].to_int().unsafe_to_char()
    s = s + "\{c}"
    i = i + 1
  }
  parse_example_expr(s)
}

// ---------------------------------------------------------------------------
// 单元测试（示例 / 边界）—— 锁定打印形式与解析行为的具体样例
// ---------------------------------------------------------------------------

///|
/// 打印器以完全括号化形式输出，嵌套结构括号唯一界定。
test "example grammar prints in fully-parenthesized form" {
  let e = ExampleExpr::Add(
    ExampleExpr::Num(1),
    ExampleExpr::Mul(ExampleExpr::Num(2), ExampleExpr::Num(3)),
  )
  inspect(print_example_expr(e), content="(1+(2*3))")
}

///|
/// 对具体 AST，解析其打印结果应得到逐结构相等的 AST（往返的具体见证）。
test "example grammar parses printed form back to equal AST" {
  let e = ExampleExpr::Mul(
    ExampleExpr::Add(ExampleExpr::Num(10), ExampleExpr::Num(20)),
    ExampleExpr::Num(3),
  )
  let s = print_example_expr(e)
  inspect(s, content="((10+20)*3)")
  assert_true(parse_example_expr(s) == Some(e))
}

///|
/// 顶层入口拒绝非法 / 不完整 / 尾随多余字符的输入（返回 None，不产生半成品）。
test "example grammar rejects malformed input" {
  assert_true(parse_example_expr("(1+)") is None) // 右子表达式缺失
  assert_true(parse_example_expr("(1+2") is None) // 缺少右括号
  assert_true(parse_example_expr("1+2") is None) // 未括号化 → 尾随未消费输入
  assert_true(parse_example_expr("") is None) // 空输入
  assert_true(parse_example_expr("(1-2)") is None) // 不支持的运算符
}

// ---------------------------------------------------------------------------
// Property 10：解析器组合子语法结构往返
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 10: 解析器组合子语法结构往返（round_trip 模板）
///
/// 对任意由生成器产出的合法语法结构 `x`，经"打印 → Bytes → 解析"的往返应
/// 还原为等价结构（`parse(print(x)) ≡ x`）。本测试复用 @infra_pbt 的
/// `round_trip` 往返断言模板，默认迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 4.5**
test "Feature: moonbit-infra-suite, Property 10: parse(print(x)) round-trips (round_trip template)" {
  let ok = @infra_pbt.round_trip(
    gen_example_expr(),
    expr_to_bytes,
    bytes_to_expr,
  )
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 10: 解析器组合子语法结构往返（holds_for_all 模板）
///
/// 同一往返性质的直接谓词形式：对任意生成的 AST `x`，
/// `parse_example_expr(print_example_expr(x))` 应恰好等于 `Some(x)`。复用
/// @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 4.5**
test "Feature: moonbit-infra-suite, Property 10: parse(print(x)) equals x (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_example_expr(), fn(x) {
    parse_example_expr(print_example_expr(x)) == Some(x)
  })
  assert_true(ok)
}
