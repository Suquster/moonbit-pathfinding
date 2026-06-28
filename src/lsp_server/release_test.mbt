// release_test.mbt —— 校验方向五（LSP）发布元数据登记（任务 14.6）。
//
// 覆盖 Requirement 11.5：
//   * 登记的 DirectionRelease 身份字段正确（name / version / changelog_path）；
//   * 发布单元名取 "lsp"（lsp_binding + lsp_server 两子包构成单一发布单元）；
//   * 版本号为合法 SemVer 且恰为骨架首版 "0.1.0"；
//   * changelog 路径指向方向入口子包实际维护的文件；
//   * 依质量门禁评估时 release_ready 与聚合判定一致。

///|
/// 登记的发布元数据身份字段正确，版本为旗舰深化版 0.2.0。
test "lsp release_info registers identity at 0.2.0" {
  let info = release_info()
  @test.assert_eq(info.name, "lsp")
  @test.assert_eq(info.version, "0.2.0")
  @test.assert_eq(info.changelog_path, "src/lsp_server/CHANGELOG.md")
}

///|
/// 登记的版本号是合法 SemVer，且恰为 0.2.0。
test "lsp version is a well-formed 0.2.0 semver" {
  assert_true(@release_meta.is_valid_semver(lsp_version))
  @test.assert_eq(
    @release_meta.parse_semver(lsp_version),
    Some({ major: 0, minor: 2, patch: 0 }),
  )
}

///|
/// 发布单元名为 "lsp"，changelog 指向方向入口子包实际维护路径。
test "lsp release identity uses unit name and entry-package changelog" {
  @test.assert_eq(lsp_name, "lsp")
  @test.assert_eq(lsp_changelog_path, "src/lsp_server/CHANGELOG.md")
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
  @test.assert_eq(ready.name, "lsp")
  @test.assert_eq(ready.version, "0.2.0")
  let blocked = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: false,
  })
  assert_false(blocked.release_ready)
}

///|
/// 任务 18.7：发布门禁真值表。
///
/// 覆盖 Requirement 11.7——三后端测试（tests_passing）/ 属性测试
/// （proofs_passing）/ 可执行文档（docs_passing）三项质量门禁，任一未过即
/// 阻止方向五进入 release-ready。下方对 2^3 = 8 个布尔组合穷举校验
/// `release_info_with_gates(...).release_ready ≡ 三项逻辑合取`：
///   * 全绿 → release_ready == true；
///   * 任一项单独失败（其余全绿）→ release_ready == false；
///   * 全红 → release_ready == false。
/// 同时确认评估不改写发布身份字段（name/version/changelog_path）。
test "lsp release gate truth table: any failing gate blocks release-ready" {
  // 全绿：唯一应当就绪的组合。
  let all_pass = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_true(all_pass.release_ready)

  // 三后端测试单独未过 → 阻止。
  assert_false(
    release_info_with_gates({
      tests_passing: false,
      proofs_passing: true,
      docs_passing: true,
    }).release_ready,
  )

  // 属性测试单独未过 → 阻止。
  assert_false(
    release_info_with_gates({
      tests_passing: true,
      proofs_passing: false,
      docs_passing: true,
    }).release_ready,
  )

  // 可执行文档单独未过 → 阻止。
  assert_false(
    release_info_with_gates({
      tests_passing: true,
      proofs_passing: true,
      docs_passing: false,
    }).release_ready,
  )

  // 全红 → 阻止。
  assert_false(
    release_info_with_gates({
      tests_passing: false,
      proofs_passing: false,
      docs_passing: false,
    }).release_ready,
  )

  // 穷举 2^3 个组合：release_ready 须严格等于三项合取；
  // 且无论门禁如何，发布身份字段保持稳定。
  let bools = [true, false]
  for t in bools {
    for p in bools {
      for d in bools {
        let dr = release_info_with_gates({
          tests_passing: t,
          proofs_passing: p,
          docs_passing: d,
        })
        @test.assert_eq(dr.release_ready, t && p && d)
        @test.assert_eq(dr.name, "lsp")
        @test.assert_eq(dr.version, "0.2.0")
        @test.assert_eq(dr.changelog_path, "src/lsp_server/CHANGELOG.md")
      }
    }
  }
}
