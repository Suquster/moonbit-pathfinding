// release_test.mbt —— 校验 Actor_Framework 方向发布元数据登记。
//
// 覆盖 Requirement 15.5 / 15.6：
//   * 登记的 DirectionRelease 身份字段正确（name / version / changelog_path）；
//   * 版本号为合法 SemVer 且恰为旗舰深化版 "0.2.0"（自骨架 0.1.0 次版本推进）；
//   * changelog 路径遵循 src/{方向}/CHANGELOG.md 约定；
//   * 依质量门禁评估时 release_ready 与聚合判定一致。

///|
/// 登记的发布元数据身份字段正确，版本为旗舰深化版 0.2.0。
test "actor release_info registers identity at 0.2.0" {
  let info = release_info()
  @test.assert_eq(info.name, "actor")
  @test.assert_eq(info.version, "0.2.0")
  @test.assert_eq(info.changelog_path, "src/actor/CHANGELOG.md")
}

///|
/// 登记的版本号是合法 SemVer，且恰为 0.2.0。
test "actor version is a well-formed 0.2.0 semver" {
  assert_true(@release_meta.is_valid_semver(actor_version))
  @test.assert_eq(
    @release_meta.parse_semver(actor_version),
    Some({ major: 0, minor: 2, patch: 0 }),
  )
}

///|
/// changelog 路径遵循 src/{方向}/CHANGELOG.md 约定。
test "actor changelog path follows convention" {
  @test.assert_eq(
    release_info().changelog_path,
    @release_meta.default_changelog_path("actor"),
  )
}

///|
/// 依门禁评估：三项全绿才就绪，否则不就绪——身份字段保持不变。
test "actor release_info_with_gates matches aggregate gate" {
  let ready = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_true(ready.release_ready)
  @test.assert_eq(ready.name, "actor")
  @test.assert_eq(ready.version, "0.2.0")
  let blocked = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: false,
  })
  assert_false(blocked.release_ready)
}

///|
/// 版本推进见证：actor_version 恰为 0.2.0，解析得 {0,2,0}；并见证
/// 0.2.0 相对 0.1.0 是一次「次版本推进」——major 不变、minor 增加
/// （Requirement 15.6 / 15.5）。
test "actor 0.2.0 witnesses a minor-version bump over 0.1.0" {
  // 当前版本字段见证：actor_version 与登记元数据一致，且解析为 {0,2,0}。
  @test.assert_eq(actor_version, "0.2.0")
  let cur = @release_meta.parse_semver(actor_version)
  @test.assert_eq(cur, Some({ major: 0, minor: 2, patch: 0 }))
  // 取出前一骨架版本与当前版本的结构化字段，逐字段比较推进性质。
  let prev = @release_meta.parse_semver("0.1.0")
  @test.assert_eq(prev, Some({ major: 0, minor: 1, patch: 0 }))
  match (prev, cur) {
    (Some(p), Some(c)) => {
      // 次版本推进：主版本不变。
      @test.assert_eq(c.major, p.major)
      // 次版本推进：次版本号增加（严格大于）。
      assert_true(c.minor > p.minor)
      // 旗舰深化在 0.x 下新增向后兼容能力，patch 归零。
      @test.assert_eq(c.patch, 0)
    }
    _ => abort("两个版本号均应为合法 SemVer")
  }
}

///|
/// 门禁聚合见证（Requirement 15.6）：枚举质量门禁三要素的代表性组合，
/// 断言 release_info_with_gates 的 release_ready 与三门禁 AND 聚合一致——
/// 三项全绿才就绪，任一未通过即阻止发布就绪；且身份字段在各组合下不变。
test "actor release readiness aggregates gates as logical AND" {
  // 各组合下身份字段应恒定不变，先固化期望值便于逐组合复核。
  let expect_name = "actor"
  let expect_version = "0.2.0"
  let expect_changelog = "src/actor/CHANGELOG.md"

  // —— 组合 1：三项全 true → 就绪。
  let all_green = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_true(all_green.release_ready)

  // —— 组合 2：tests=false → 不就绪（未通过则阻止发布就绪）。
  let no_tests = release_info_with_gates({
    tests_passing: false,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_false(no_tests.release_ready)

  // —— 组合 3：proofs=false → 不就绪。
  let no_proofs = release_info_with_gates({
    tests_passing: true,
    proofs_passing: false,
    docs_passing: true,
  })
  assert_false(no_proofs.release_ready)

  // —— 组合 4：docs=false → 不就绪。
  let no_docs = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: false,
  })
  assert_false(no_docs.release_ready)

  // 与 release_meta 的纯聚合函数交叉见证：评估结果应与 AND 聚合逐一吻合。
  @test.assert_eq(
    all_green.release_ready,
    @release_meta.aggregate_release_ready({
      tests_passing: true,
      proofs_passing: true,
      docs_passing: true,
    }),
  )
  @test.assert_eq(
    no_tests.release_ready,
    @release_meta.release_ready_of(false, true, true),
  )
  @test.assert_eq(
    no_proofs.release_ready,
    @release_meta.release_ready_of(true, false, true),
  )
  @test.assert_eq(
    no_docs.release_ready,
    @release_meta.release_ready_of(true, true, false),
  )

  // 身份字段（name / version / changelog_path）在各组合下保持不变。
  for info in [all_green, no_tests, no_proofs, no_docs] {
    @test.assert_eq(info.name, expect_name)
    @test.assert_eq(info.version, expect_version)
    @test.assert_eq(info.changelog_path, expect_changelog)
  }
}
