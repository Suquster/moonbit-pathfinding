// lookahead_prop_test.mbt —— L0 前瞻 / 否定前瞻属性测试（task 3.2）。
//
// 以全称量化形式实现 Property 15：`lookahead(p)` 与 `not_followed_by(p)` 的零
// 消费不变量与成功条件。复用 @infra_pbt 与本包共享生成器。

///|
/// Feature: parser-combinator, Property 15: 前瞻与否定前瞻零消费不变量
///
/// 对任意解析器 `p` 与输入：
///   * `lookahead(p)` 成功 ⟺ `p` 成功；成功时产出 `p` 的值且剩余输入偏移等于
///     进入偏移（零消费）。
///   * `not_followed_by(p)` 成功 ⟺ `p` 失败；成功时剩余输入偏移等于进入偏移；
///     当 `p` 成功时 `not_followed_by(p)` 在进入位置失败。
///
/// **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**
test "Feature: parser-combinator, Property 15: lookahead/not_followed_by zero consumption" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (p, s) = pair
    let pr = p.parse_string(s)
    let la = lookahead(p).parse_string(s)
    let nfb = not_followed_by(p).parse_string(s)
    // lookahead：成功⟺p成功；成功零消费且产出一致。
    let la_ok = match (pr, la) {
      (Ok(v1, _), Ok(v2, rest)) => v1 == v2 && rest.pos.offset == 0
      (Fail(_, ..), Fail(_, ..)) => true
      _ => false
    }
    // not_followed_by：p成功→进入位置失败；p失败→零消费成功。
    let nfb_ok = match (pr, nfb) {
      (Ok(_, _), Fail(pos, ..)) => pos.offset == 0
      (Fail(_, ..), Ok(_, rest)) => rest.pos.offset == 0
      _ => false
    }
    la_ok && nfb_ok
  })
  assert_true(ok)
}
