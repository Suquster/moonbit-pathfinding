// release_test.mbt —— 校验 Parser_Combinator 方向发布元数据登记（任务 5.6）。
//
// 覆盖 Requirement 11.5：
//   * 登记的 DirectionRelease 身份字段正确（name / version / changelog_path）；
//   * 版本号为合法 SemVer 且恰为骨架首版 "0.1.0"；
//   * changelog 路径遵循 src/{方向}/CHANGELOG.md 约定；
//   * 依质量门禁评估时 release_ready 与聚合判定一致。

///|
/// 登记的发布元数据身份字段正确，版本为旗舰深化版 0.2.0。
test "parser_combinator release_info registers identity at 0.2.0" {
  let info = release_info()
  assert_eq(info.name, "parser_combinator")
  assert_eq(info.version, "0.2.0")
  assert_eq(info.changelog_path, "src/parser_combinator/CHANGELOG.md")
}

///|
/// 登记的版本号是合法 SemVer，且恰为 0.2.0。
test "parser_combinator version is a well-formed 0.2.0 semver" {
  assert_true(@release_meta.is_valid_semver(parser_combinator_version))
  assert_eq(
    @release_meta.parse_semver(parser_combinator_version),
    Some({ major: 0, minor: 2, patch: 0 }),
  )
}

///|
/// changelog 路径遵循 src/{方向}/CHANGELOG.md 约定。
test "parser_combinator changelog path follows convention" {
  assert_eq(
    release_info().changelog_path,
    @release_meta.default_changelog_path("parser_combinator"),
  )
}

///|
/// 依门禁评估：三项全绿才就绪，否则不就绪——身份字段保持不变。
test "parser_combinator release_info_with_gates matches aggregate gate" {
  let ready = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_true(ready.release_ready)
  assert_eq(ready.name, "parser_combinator")
  assert_eq(ready.version, "0.2.0")
  let blocked = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: false,
  })
  assert_false(blocked.release_ready)
}
