// release_test.mbt —— 校验方向五（LSP）发布元数据登记（任务 14.6）。
//
// 覆盖 Requirement 11.5：
//   * 登记的 DirectionRelease 身份字段正确（name / version / changelog_path）；
//   * 发布单元名取 "lsp"（lsp_binding + lsp_server 两子包构成单一发布单元）；
//   * 版本号为合法 SemVer 且恰为骨架首版 "0.1.0"；
//   * changelog 路径指向方向入口子包实际维护的文件；
//   * 依质量门禁评估时 release_ready 与聚合判定一致。

///|
/// 登记的发布元数据身份字段正确，版本为骨架首版 0.1.0。
test "lsp release_info registers identity at 0.1.0" {
  let info = release_info()
  assert_eq(info.name, "lsp")
  assert_eq(info.version, "0.1.0")
  assert_eq(info.changelog_path, "src/lsp_server/CHANGELOG.md")
}

///|
/// 登记的版本号是合法 SemVer，且恰为 0.1.0。
test "lsp version is a well-formed 0.1.0 semver" {
  assert_true(@release_meta.is_valid_semver(lsp_version))
  assert_eq(
    @release_meta.parse_semver(lsp_version),
    Some({ major: 0, minor: 1, patch: 0 }),
  )
}

///|
/// 发布单元名为 "lsp"，changelog 指向方向入口子包实际维护路径。
test "lsp release identity uses unit name and entry-package changelog" {
  assert_eq(lsp_name, "lsp")
  assert_eq(lsp_changelog_path, "src/lsp_server/CHANGELOG.md")
}

///|
/// 依门禁评估：三项全绿才就绪，否则不就绪——身份字段保持不变。
test "lsp release_info_with_gates matches aggregate gate" {
  let ready = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_true(ready.release_ready)
  assert_eq(ready.name, "lsp")
  assert_eq(ready.version, "0.1.0")
  let blocked = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: false,
  })
  assert_false(blocked.release_ready)
}
