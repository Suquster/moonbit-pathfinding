// release_gate_test.mbt —— 发布门禁真值表回归测试（任务 16.2）。
//
// 覆盖 Requirement 13.7：三后端测试 / 证明谓词 / 可执行文档任一未过时，
// `release_info_with_gates` 阻止本方向进入 release-ready；并固化 `release_info`
// 身份字段稳定性。

///|
/// 门禁真值表：仅当三项全绿才就绪，任一项未过即阻止 release-ready。
test "release gate blocks release-ready unless all gates pass" {
  // 三项全绿 → 就绪。
  assert_true(
    release_info_with_gates({
      tests_passing: true,
      proofs_passing: true,
      docs_passing: true,
    }).release_ready,
  )
  // 任一项未过 → 阻止。
  assert_false(
    release_info_with_gates({
      tests_passing: false,
      proofs_passing: true,
      docs_passing: true,
    }).release_ready,
  )
  assert_false(
    release_info_with_gates({
      tests_passing: true,
      proofs_passing: false,
      docs_passing: true,
    }).release_ready,
  )
  assert_false(
    release_info_with_gates({
      tests_passing: true,
      proofs_passing: true,
      docs_passing: false,
    }).release_ready,
  )
}

///|
/// release_info 身份字段稳定（name / changelog 路径不随门禁变化）。
test "release_info identity is stable across gate evaluation" {
  let blocked = release_info_with_gates({
    tests_passing: false,
    proofs_passing: false,
    docs_passing: false,
  })
  @test.assert_eq(blocked.name, "logging")
  @test.assert_eq(blocked.version, logging_version)
  @test.assert_eq(blocked.changelog_path, "src/logging/CHANGELOG.md")
  assert_false(blocked.release_ready)
}
