// release_test.mbt —— 校验 Codegen_Infra 方向发布元数据登记（任务 11.6）。
//
// 覆盖 Requirement 11.5：
//   * 登记的 DirectionRelease 身份字段正确（name / version / changelog_path）；
//   * 版本号为合法 SemVer 且恰为骨架首版 "0.1.0"；
//   * changelog 路径遵循 src/{方向}/CHANGELOG.md 约定；
//   * 依质量门禁评估时 release_ready 与聚合判定一致。

///|
/// 登记的发布元数据身份字段正确，版本为旗舰深化次版本 0.2.0。
test "codegen_infra release_info registers identity at 0.2.0" {
  let info = release_info()
  @test.assert_eq(info.name, "codegen_infra")
  @test.assert_eq(info.version, "0.2.0")
  @test.assert_eq(info.changelog_path, "src/codegen_infra/CHANGELOG.md")
}

///|
/// 登记的版本号是合法 SemVer，且恰为 0.2.0。
test "codegen_infra version is a well-formed 0.2.0 semver" {
  assert_true(@release_meta.is_valid_semver(codegen_infra_version))
  @test.assert_eq(
    @release_meta.parse_semver(codegen_infra_version),
    Some({ major: 0, minor: 2, patch: 0 }),
  )
}

///|
/// changelog 路径遵循 src/{方向}/CHANGELOG.md 约定。
test "codegen_infra changelog path follows convention" {
  @test.assert_eq(
    release_info().changelog_path,
    @release_meta.default_changelog_path("codegen_infra"),
  )
}

///|
/// 依门禁评估：三项全绿才就绪，否则不就绪——身份字段保持不变。
test "codegen_infra release_info_with_gates matches aggregate gate" {
  let ready = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_true(ready.release_ready)
  @test.assert_eq(ready.name, "codegen_infra")
  @test.assert_eq(ready.version, "0.2.0")
  let blocked = release_info_with_gates({
    tests_passing: true,
    proofs_passing: false,
    docs_passing: true,
  })
  assert_false(blocked.release_ready)
}

///|
/// 发布门禁真值表（任务 19.6）：三后端测试 / 属性测试 / 可执行文档任一未过即阻止
/// release-ready；三项全绿方就绪。
/// _Requirements: 16.1, 16.2, 16.6_
test "codegen_infra release gate truth table blocks on any failing gate" {
  // 三项全绿 → 就绪。
  assert_true(
    release_info_with_gates({
      tests_passing: true,
      proofs_passing: true,
      docs_passing: true,
    }).release_ready,
  )
  // 任一未过 → 阻止就绪。
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
  // 全未过 → 阻止就绪。
  assert_false(
    release_info_with_gates({
      tests_passing: false,
      proofs_passing: false,
      docs_passing: false,
    }).release_ready,
  )
}
