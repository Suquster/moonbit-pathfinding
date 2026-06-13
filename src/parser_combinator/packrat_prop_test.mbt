// packrat_prop_test.mbt —— L1 packrat 记忆化属性测试与入口 smoke 测试
// （tasks 8.2, 8.3, 8.4）。
//
// 实现 Property 23（packrat 与朴素差分一致性）、Property 24（packrat 缓存隔离），
// 并补充 run_packrat / run_naive 入口切换的 smoke 测试。

///|
/// Feature: parser-combinator, Property 23: packrat 与朴素差分一致性
///
/// 对任意富解析器与输入，`run_packrat` 与 `run_naive` 产生逐字段一致的解析结果
/// （含产出值、剩余输入位置与失败诊断）；并且在同一输入位置以同一被记忆解析器
/// 重复求值返回逐字段一致的结果（由记忆化命中返回缓存保证）。
///
/// **Validates: Requirements 8.1, 8.2, 8.3**
test "Feature: parser-combinator, Property 23: packrat-naive differential consistency" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    (gen_grammar().generate(rng), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(pair) {
    let (g, s) = pair
    let packrat = g.run_packrat_string(s)
    let naive = g.run_naive_string(s)
    // 差分一致；并校验同一位置重复求值（再跑一次 packrat）逐字段一致。
    let packrat2 = g.run_packrat_string(s)
    gresult_eq(packrat, naive) && gresult_eq(packrat, packrat2)
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 24: packrat 缓存隔离
///
/// 对任意两段不同输入，连续以 `run_packrat` 解析时，前一次运行不污染后一次：
/// 在 `s1` → `s2` → `s1` 的交错运行序列中，`s1` 的两次结果逐字段一致（缓存
/// 生命周期限定于单次运行，不同输入互不污染）。
///
/// **Validates: Requirements 8.5**
test "Feature: parser-combinator, Property 24: packrat cache isolation" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    (gen_grammar_at(rng, 3), gen_input_str(rng), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(triple) {
    let (g, s1, s2) = triple
    let r1_first = g.run_packrat_string(s1)
    let _ = g.run_packrat_string(s2) // 交错的另一输入运行
    let r1_again = g.run_packrat_string(s1)
    // s1 的结果不受中间 s2 运行影响（缓存隔离）。
    gresult_eq(r1_first, r1_again)
  })
  assert_true(ok)
}

///|
/// packrat 入口 smoke：调用方无需改动文法即可在 run_packrat / run_naive 间切换
/// （R8.4），且对同一确定性文法两者结果一致。
test "packrat entry switches without modifying the grammar" {
  let digit = lift(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字"))
  let g = many1_grammar(digit) // 同一文法，下方两种入口运行
  let packrat = g.run_packrat_string("123x")
  let naive = g.run_naive_string("123x")
  assert_true(gresult_eq_int_list(packrat, naive))
  assert_true(packrat.is_ok())
}

///|
/// 测试辅助：把数字字符富解析器重复≥1次收集为 Int 列表（借 L0 many1 再 lift）。
fn many1_grammar(_g : Grammar[Char]) -> Grammar[Array[Int]] {
  // 直接以 L0 many1 构造再 lift，聚焦验证引擎入口切换而非重写 many。
  lift(
    map(many1(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")), fn(
      chars,
    ) {
      let acc : Array[Int] = []
      for c in chars {
        acc.push(c.to_int() - '0'.to_int())
      }
      acc
    }),
  )
}

///|
/// 测试辅助：Array[Int] 解析结果的逐字段比较。
fn gresult_eq_int_list(
  a : ParseResult[Array[Int]],
  b : ParseResult[Array[Int]],
) -> Bool {
  match (a, b) {
    (Ok(v1, r1), Ok(v2, r2)) => v1 == v2 && r1.pos.offset == r2.pos.offset
    (Fail(p1, expected=e1), Fail(p2, expected=e2)) =>
      p1.offset == p2.offset && e1 == e2
    _ => false
  }
}
