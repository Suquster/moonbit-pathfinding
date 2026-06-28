// derived_prop_test.mbt —— L0 衍生组合子属性测试与边界单元测试（tasks 2.2~2.5）。
//
// 以全称量化形式实现 Property 11~14（sep_by 家族收集语义、between 仅产出主体、
// chainl1 左结合、chainr1 右结合），并补充 `chainl`/`chainr` 空序列与 `lazy_parser`
// 递归不发散的边界单元测试。复用 @infra_pbt 模板与本包共享随机源。

// ---------------------------------------------------------------------------
// 测试辅助：数字 / 运算符解析器与参照折叠
// ---------------------------------------------------------------------------

///|
/// 数字解析器：`digit+` → 非负整数（无前导符号）。
fn dp_number() -> Parser[Int] {
  map(many1(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")), fn(
    chars,
  ) {
    let mut n = 0
    for c in chars {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
    n
  })
}

///|
/// 减法运算符解析器（左 / 右结合差异敏感）：`'-'` → `fn(a, b) { a - b }`。
fn dp_sub_op() -> Parser[(Int, Int) -> Int] {
  map(pchar('-'), fn(_c) { fn(a : Int, b : Int) -> Int { a - b } })
}

///|
/// 把整数序列以 `,` 连接为输入文本（供 sep_by 测试）。
fn join_commas(xs : Array[Int]) -> String {
  let mut s = ""
  for i, x in xs {
    if i > 0 {
      s = s + ","
    }
    s = s + "\{x}"
  }
  s
}

///|
/// 把整数序列以 `-` 连接为输入文本（供 chain 测试）。
fn join_minus(xs : Array[Int]) -> String {
  let mut s = ""
  for i, x in xs {
    if i > 0 {
      s = s + "-"
    }
    s = s + "\{x}"
  }
  s
}

///|
/// 生成长度 `lo`~`hi`、元素取值 `[0, vmax]` 的整数序列。
fn gen_int_list(
  rng : @infra_pbt.Rng,
  lo : Int,
  hi : Int,
  vmax : Int,
) -> Array[Int] {
  let len = rng.next_range(lo, hi)
  let xs : Array[Int] = []
  let mut i = 0
  while i < len {
    xs.push(rng.next_range(0, vmax))
    i = i + 1
  }
  xs
}

// ---------------------------------------------------------------------------
// Property 11：sep_by 家族收集语义
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 11: sep_by 家族收集语义
///
/// 对任意元素序列：`sep_by(number, ',')` 收集出的数组等于该序列（零元素时为空
/// 数组且不消费输入）；`sep_by1` 在零元素输入上于起始位置失败、在一个或多个
/// 元素时与 `sep_by` 收集一致。
///
/// **Validates: Requirements 3.1, 3.2**
test "Feature: parser-combinator, Property 11: sep_by family collection semantics" {
  let gen = @infra_pbt.Gen::new(fn(rng) { gen_int_list(rng, 0, 5, 99) })
  let ok = @infra_pbt.holds_for_all(gen, fn(xs) {
    let input = join_commas(xs)
    let by = sep_by(dp_number(), pchar(','))
    let by1 = sep_by1(dp_number(), pchar(','))
    let r = by.parse_string(input)
    let collected_ok = match r {
      Ok(arr, rest) => arr == xs && rest.is_eof()
      Fail(_, ..) => false
    }
    if xs.length() == 0 {
      // 零元素：sep_by → [] 且不消费；sep_by1 → 在起始位置失败。
      let empty_rest = match by.parse_string("") {
        Ok(arr, rest) => arr.length() == 0 && rest.pos.offset == 0
        Fail(_, ..) => false
      }
      let by1_fails = match by1.parse_string("") {
        Fail(pos, ..) => pos.offset == 0
        Ok(_, _) => false
      }
      collected_ok && empty_rest && by1_fails
    } else {
      // 非空：sep_by1 收集结果应与 sep_by 一致。
      let by1_ok = match by1.parse_string(input) {
        Ok(arr, _) => arr == xs
        Fail(_, ..) => false
      }
      collected_ok && by1_ok
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 12：between 仅产出主体并消费三段
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 12: between 仅产出主体并消费三段
///
/// 对任意 `(数字)` 形式的输入，`between('(', number, ')')` 产出该数字且剩余输入
/// 落在 `)` 之后（消费三段覆盖的全部输入）。
///
/// **Validates: Requirements 3.3**
test "Feature: parser-combinator, Property 12: between yields body and consumes all three" {
  let gen = @infra_pbt.Gen::new(fn(rng) { rng.next_range(0, 9999) })
  let ok = @infra_pbt.holds_for_all(gen, fn(n) {
    let input = "(" + "\{n}" + ")"
    match between(pchar('('), dp_number(), pchar(')')).parse_string(input) {
      Ok(v, rest) => v == n && rest.is_eof()
      Fail(_, ..) => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 13：chainl1 左结合一致
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 13: chainl1 左结合一致
///
/// 对任意操作数序列与减法运算符，`chainl1(number, '-')` 的结果等于对同一序列
/// **自左向右**显式折叠的参照结果（左结合：`((a - b) - c) ...`）。
///
/// **Validates: Requirements 3.4**
test "Feature: parser-combinator, Property 13: chainl1 is left-associative" {
  let gen = @infra_pbt.Gen::new(fn(rng) { gen_int_list(rng, 1, 5, 20) })
  let ok = @infra_pbt.holds_for_all(gen, fn(xs) {
    let input = join_minus(xs)
    // 参照：自左向右折叠。
    let mut acc = xs[0]
    let mut i = 1
    while i < xs.length() {
      acc = acc - xs[i]
      i = i + 1
    }
    match chainl1(dp_number(), dp_sub_op()).parse_string(input) {
      Ok(v, rest) => v == acc && rest.is_eof()
      Fail(_, ..) => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 14：chainr1 右结合一致
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 14: chainr1 右结合一致
///
/// 对任意操作数序列与减法运算符，`chainr1(number, '-')` 的结果等于对同一序列
/// **自右向左**显式折叠的参照结果（右结合：`a - (b - (c ...))`）。
///
/// **Validates: Requirements 3.5**
test "Feature: parser-combinator, Property 14: chainr1 is right-associative" {
  let gen = @infra_pbt.Gen::new(fn(rng) { gen_int_list(rng, 1, 5, 20) })
  let ok = @infra_pbt.holds_for_all(gen, fn(xs) {
    let input = join_minus(xs)
    // 参照：自右向左折叠。
    let mut acc = xs[xs.length() - 1]
    let mut i = xs.length() - 2
    while i >= 0 {
      acc = xs[i] - acc
      i = i - 1
    }
    match chainr1(dp_number(), dp_sub_op()).parse_string(input) {
      Ok(v, rest) => v == acc && rest.is_eof()
      Fail(_, ..) => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// 边界单元测试（task 2.5）：chainl/chainr 空序列 · lazy_parser 递归不发散
// ---------------------------------------------------------------------------

///|
/// chainl / chainr 在零操作数（空输入）时产出 default 且不消费输入（R3.6）。
test "chainl/chainr yield default on empty operand sequence without consuming" {
  let cl = chainl(dp_number(), dp_sub_op(), -1)
  match cl.parse_string("") {
    Ok(v, rest) => {
      @test.assert_eq(v, -1)
      @test.assert_eq(rest.pos.offset, 0)
    }
    Fail(_, ..) => fail("chainl should yield default on empty")
  }
  let cr = chainr(dp_number(), dp_sub_op(), -2)
  match cr.parse_string("") {
    Ok(v, rest) => {
      @test.assert_eq(v, -2)
      @test.assert_eq(rest.pos.offset, 0)
    }
    Fail(_, ..) => fail("chainr should yield default on empty")
  }
  // 非空时退化为 chainl1 / chainr1。
  assert_true(
    chainl(dp_number(), dp_sub_op(), -1).parse_string("8-3-2").value() ==
    Some(3),
  )
}

///|
/// 递归嵌套括号深度解析器：经 `lazy_parser` 打破构造期循环，运行时不发散（R3.7）。
fn dp_nested_depth() -> Parser[Int] {
  lazy_parser(fn() {
    alt([
      map(between(pchar('('), dp_nested_depth(), pchar(')')), fn(d) { d + 1 }),
      pure(0),
    ])
  })
}

///|
/// lazy_parser 支持递归文法定义且运行时收敛（不发散）。
test "lazy_parser supports recursive grammar without divergence" {
  // 三层嵌套括号 → 深度 3。
  match dp_nested_depth().parse_string("((()))") {
    Ok(v, rest) => {
      @test.assert_eq(v, 3)
      assert_true(rest.is_eof())
    }
    Fail(_, ..) => fail("expected nested parens to parse")
  }
  // 无括号 → 深度 0，不消费输入。
  match dp_nested_depth().parse_string("x") {
    Ok(v, rest) => {
      @test.assert_eq(v, 0)
      @test.assert_eq(rest.pos.offset, 0)
    }
    Fail(_, ..) => fail("expected zero-depth success")
  }
}
