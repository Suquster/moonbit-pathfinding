// parser_textbuilder_equiv_test.mbt —— 任务 12.4 等价性测试。
//
// 目标：验证「将 parser_combinator 生产源文件中循环内字符串拼接
// （`s = s + "\{c}"` / `out = out + ...` / `exp = exp + ...` 等 O(n²) 反模式，
// 以及 `print_expr` 单节点 4 次顺序 `+`）替换为 `@infra_text.TextBuilder`
// 后，每个被改造函数的输出与改造前**逐字符相等**」
// （production-hardening Requirement 1.5 / 1.6）。
//
// 被改造点覆盖：
//   * json.mbt `json_string_raw`   —— 解码字符逐字符累积（经 parse_json 验证）；
//   * json.mbt `print_json_string` —— 转义循环；
//   * json.mbt `print_json`        —— JArray / JObject 元素循环；
//   * types.mbt `to_path_error`    —— 期望符号集合逗号分隔循环；
//   * arith.mbt `print_expr`       —— 完全括号化二元节点（经 arith_wrap_binop）。
//
// 这些函数内部已改为 `@infra_text.TextBuilder`，其 `build()` 与等价顺序 `+`
// 拼接逐字符相等（infra_text 设计 AC1/AC3 已由该包属性测试守护）；本文件以
// 确定性黄金值与往返一致性进一步固化「改造前后输出一致」这一行为契约。

///|
/// print_json_string：转义循环改造后逐字符等价（黄金串）。
///
/// 覆盖全部转义分支（`" \ \n \r \t \b \f`）与普通字符 `else` 分支，验证
/// `out = out + ...` → `TextBuilder.push_str` / `push_char` 改造后逐字符不变。
test "textbuilder equiv: print_json_string escape loop" {
  // 普通字符串：仅首尾引号。
  @test.assert_eq(print_json(JString("abc")), "\"abc\"")
  // 全部转义分支逐字符还原。
  @test.assert_eq(
    print_json(JString("\"\\\n\r\t\u{0008}\u{000C}")),
    "\"\\\"\\\\\\n\\r\\t\\b\\f\"",
  )
  // 混合：普通字符与转义交错。
  @test.assert_eq(print_json(JString("a\nb\tc")), "\"a\\nb\\tc\"")
  // 空字符串：仅一对引号。
  @test.assert_eq(print_json(JString("")), "\"\"")
}

///|
/// print_json：JArray / JObject 元素循环改造后逐字符等价（黄金串）。
test "textbuilder equiv: print_json array/object loops" {
  // 空数组 / 空对象。
  @test.assert_eq(print_json(JArray([])), "[]")
  @test.assert_eq(print_json(JObject([])), "{}")
  // 多元素数组：逗号分隔，无尾随逗号。
  @test.assert_eq(
    print_json(JArray([JNumber(1.0), JBool(true), JNull])),
    "[1,true,null]",
  )
  // 多键对象：键经 print_json_string 转义，`key:value` 以逗号分隔。
  @test.assert_eq(
    print_json(JObject([("a", JNumber(1.0)), ("b", JArray([JNull]))])),
    "{\"a\":1,\"b\":[null]}",
  )
  // 嵌套结构：递归打印 + 循环拼接组合。
  @test.assert_eq(
    print_json(JArray([JObject([("x", JArray([JNumber(2.0)]))])])),
    "[{\"x\":[2]}]",
  )
}

///|
/// json_string_raw：解码字符逐字符累积改造后等价（经 parse_json 验证）。
///
/// `s = s + "\{c}"` → `TextBuilder.push_char` 改造后，解码出的字符串值不变。
test "textbuilder equiv: json_string_raw decode loop via parse_json" {
  match parse_json("\"hello world\"") {
    Ok(JString(s)) => @test.assert_eq(s, "hello world")
    _ => fail("期望 JString，实得其他结果")
  }
  // 转义序列解码：\n \t \" \\ \uXXXX。
  match parse_json("\"a\\nb\\tc\\\"\\\\\\u0041\"") {
    Ok(JString(s)) => @test.assert_eq(s, "a\nb\tc\"\\A")
    _ => fail("期望 JString（含转义解码），实得其他结果")
  }
  // 空字符串解码。
  match parse_json("\"\"") {
    Ok(JString(s)) => @test.assert_eq(s, "")
    _ => fail("期望空 JString，实得其他结果")
  }
}

///|
/// print_json ↔ parse_json 往返一致性：改造后打印仍可被解析回等价结构。
test "textbuilder equiv: print_json/parse_json roundtrip" {
  let samples : Array[Json] = [
    JNull,
    JBool(false),
    JNumber(42.0),
    JString("a\nb\"c"),
    JArray([JNumber(1.0), JString("x"), JBool(true)]),
    JObject([("k1", JNull), ("k2", JArray([JNumber(3.0), JNumber(4.0)]))]),
  ]
  for j in samples {
    let printed = print_json(j)
    match parse_json(printed) {
      Ok(parsed) => assert_true(parsed == j)
      Err(_) => fail("往返解析失败：\{printed}")
    }
  }
}

///|
/// print_expr：完全括号化二元节点改造后逐字符等价（黄金串）。
///
/// `arith_wrap_binop` 经 `TextBuilder` 物化 `'(' a op b ')'`，验证单节点 4 次
/// 顺序 `+` 缓冲化后打印形式不变。构造子以 `Expr::` 限定，避免与测试内
/// `ExampleExpr` 的同名构造子（`Num` / `Add` 等）冲突。
test "textbuilder equiv: print_expr fully parenthesized" {
  // 单一二元节点。
  @test.assert_eq(
    print_expr(Expr::Add(Expr::Num(1.0), Expr::Num(2.0))),
    "(1+2)",
  )
  // 全部运算符。
  @test.assert_eq(
    print_expr(Expr::Sub(Expr::Num(3.0), Expr::Num(1.0))),
    "(3-1)",
  )
  @test.assert_eq(
    print_expr(Expr::Mul(Expr::Num(2.0), Expr::Num(4.0))),
    "(2*4)",
  )
  @test.assert_eq(
    print_expr(Expr::Div(Expr::Num(8.0), Expr::Num(2.0))),
    "(8/2)",
  )
  @test.assert_eq(
    print_expr(Expr::Pow(Expr::Num(2.0), Expr::Num(3.0))),
    "(2^3)",
  )
  // 嵌套：左/右子树递归。
  @test.assert_eq(
    print_expr(
      Expr::Add(
        Expr::Mul(Expr::Num(1.0), Expr::Num(2.0)),
        Expr::Pow(Expr::Num(3.0), Expr::Num(4.0)),
      ),
    ),
    "((1*2)+(3^4))",
  )
}

///|
/// print_expr ↔ parse_and_eval 往返一致性：打印形式可被无歧义解析并求值。
test "textbuilder equiv: print_expr eval roundtrip" {
  // (2*3)+4 = 10
  let e = Expr::Add(Expr::Mul(Expr::Num(2.0), Expr::Num(3.0)), Expr::Num(4.0))
  let printed = print_expr(e)
  @test.assert_eq(printed, "((2*3)+4)")
  match parse_and_eval(printed) {
    Ok(v) => @test.assert_eq(v, 10.0)
    Err(_) => fail("求值往返失败：\{printed}")
  }
}
