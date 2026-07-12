// 黑盒测试：覆盖率审计收口（INFRA 第七十九批）——
// 最左最长语义下后到候选起点更靠左时的替换收敛。

///|
test "LeftmostLongest：后到候选起点更靠左时取而代之" {
  guard @regex_engine.Pattern::compile(
      "a|ba",
      kind=@regex_engine.MatchKind::LeftmostLongest,
    )
    is Ok(p)
  guard p.find("ba") is Some(m)
  assert_eq((m.start, m.end), (0, 2))
}
