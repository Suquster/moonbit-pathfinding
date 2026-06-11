// release_test.mbt —— 校验 Mini_Compiler 方向发布元数据登记（任务 15.7）。
//
// 覆盖 Requirement 11.5：
//   * 登记的 DirectionRelease 身份字段正确（name / version / changelog_path）；
//   * 版本号为合法 SemVer 且恰为骨架首版 "0.1.0"；
//   * changelog 路径遵循 src/{方向}/CHANGELOG.md 约定；
//   * 依质量门禁评估时 release_ready 与聚合判定一致。

///|
/// 登记的发布元数据身份字段正确，版本为骨架首版 0.1.0。
test "mini_compiler release_info registers identity at 0.1.0" {
  let info = release_info()
  assert_eq(info.name, "mini_compiler")
  assert_eq(info.version, "0.1.0")
  assert_eq(info.changelog_path, "src/mini_compiler/CHANGELOG.md")
}

///|
/// 登记的版本号是合法 SemVer，且恰为 0.1.0。
test "mini_compiler version is a well-formed 0.1.0 semver" {
  assert_true(@release_meta.is_valid_semver(mini_compiler_version))
  assert_true(
    @release_meta.parse_semver(mini_compiler_version) ==
    Some({ major: 0, minor: 1, patch: 0 }),
  )
}

///|
/// changelog 路径遵循 src/{方向}/CHANGELOG.md 约定。
test "mini_compiler changelog path follows convention" {
  assert_eq(
    release_info().changelog_path,
    @release_meta.default_changelog_path("mini_compiler"),
  )
}

///|
/// 依门禁评估：三项全绿才就绪，否则不就绪——身份字段保持不变。
test "mini_compiler release_info_with_gates matches aggregate gate" {
  let ready = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_true(ready.release_ready)
  assert_eq(ready.name, "mini_compiler")
  assert_eq(ready.version, "0.1.0")
  let blocked = release_info_with_gates({
    tests_passing: true,
    proofs_passing: false,
    docs_passing: true,
  })
  assert_false(blocked.release_ready)
}
