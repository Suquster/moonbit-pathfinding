// release_meta_test.mbt —— 发布元数据模型与 release-ready 聚合门禁的测试。
//
// 覆盖：
//   * 聚合判定纯函数在三项布尔输入上的真值（含穷举性质测试）；
//   * `DirectionRelease::evaluate` 与聚合判定保持一致；
//   * SemVer 解析 / 校验的合法与非法用例；
//   * changelog 约定路径。
//
// 说明：聚合判定的输入空间为 2^3 = 8 个布尔组合，故下方「穷举性质测试」
// 对全部组合校验 `aggregate_release_ready ≡ 逻辑合取`，等价于对该不变量的
// 完全证明（exhaustive property over the entire input space）。

///|
/// 聚合门禁：仅当三项门禁全绿时才为 release-ready。
test "aggregate_release_ready requires all three gates green" {
  assert_true(
    aggregate_release_ready({
      tests_passing: true,
      proofs_passing: true,
      docs_passing: true,
    }),
  )
  assert_false(
    aggregate_release_ready({
      tests_passing: false,
      proofs_passing: true,
      docs_passing: true,
    }),
  )
  assert_false(
    aggregate_release_ready({
      tests_passing: true,
      proofs_passing: false,
      docs_passing: true,
    }),
  )
  assert_false(
    aggregate_release_ready({
      tests_passing: true,
      proofs_passing: true,
      docs_passing: false,
    }),
  )
}

///|
/// 穷举性质：对 2^3 个布尔组合，聚合判定恒等于三项的逻辑合取。
/// 该测试覆盖整个输入空间，是对「全绿才就绪」不变量的完全验证。
test "property: aggregate equals logical conjunction over all inputs" {
  let bools = [true, false]
  for t in bools {
    for p in bools {
      for d in bools {
        let expected = t && p && d
        // 结构体入口
        let g : QualityGates = {
          tests_passing: t,
          proofs_passing: p,
          docs_passing: d,
        }
        assert_eq(aggregate_release_ready(g), expected)
        // 裸布尔入口，两条入口须等价
        assert_eq(release_ready_of(t, p, d), expected)
        // evaluate 计算出的 release_ready 须与聚合判定一致
        let dr = DirectionRelease::evaluate(
          "demo", "0.1.0", "src/demo/CHANGELOG.md", g,
        )
        assert_eq(dr.release_ready, expected)
      }
    }
  }
}

///|
/// evaluate 在门禁全绿时产出 release_ready=true，并保留发布身份字段。
test "DirectionRelease::evaluate preserves identity and computes readiness" {
  let dr = DirectionRelease::evaluate(
    "regex_engine",
    "0.1.0",
    "src/regex_engine/CHANGELOG.md",
    { tests_passing: true, proofs_passing: true, docs_passing: true },
  )
  assert_eq(dr.name, "regex_engine")
  assert_eq(dr.version, "0.1.0")
  assert_eq(dr.changelog_path, "src/regex_engine/CHANGELOG.md")
  assert_true(dr.release_ready)
}

///|
/// evaluate 在任一门禁未通过时拒绝进入 release-ready。
test "DirectionRelease::evaluate blocks release when a gate fails" {
  let dr = DirectionRelease::evaluate(
    "regex_engine",
    "0.1.0",
    "src/regex_engine/CHANGELOG.md",
    { tests_passing: true, proofs_passing: false, docs_passing: true },
  )
  assert_false(dr.release_ready)
}

///|
/// new 构造保留显式给定的 release_ready。
test "DirectionRelease::new keeps explicit fields" {
  let dr = DirectionRelease::new("dst", "0.2.1", "src/dst/CHANGELOG.md", false)
  assert_eq(dr.name, "dst")
  assert_eq(dr.version, "0.2.1")
  assert_eq(dr.changelog_path, "src/dst/CHANGELOG.md")
  assert_false(dr.release_ready)
}

///|
/// SemVer 解析：合法三段版本号。
test "parse_semver accepts well-formed versions" {
  assert_eq(parse_semver("0.1.0"), Some({ major: 0, minor: 1, patch: 0 }))
  assert_eq(parse_semver("1.2.3"), Some({ major: 1, minor: 2, patch: 3 }))
  assert_eq(parse_semver("10.20.30"), Some({ major: 10, minor: 20, patch: 30 }))
}

///|
/// SemVer 解析：拒绝段数错误、含前缀 / 字母 / 空段的非法输入。
test "parse_semver rejects malformed versions" {
  assert_eq(parse_semver("1.2"), None) // 段数不足
  assert_eq(parse_semver("1.2.3.4"), None) // 段数过多
  assert_eq(parse_semver("v1.2.3"), None) // 含 v 前缀
  assert_eq(parse_semver("1.2.x"), None) // 含字母
  assert_eq(parse_semver(""), None) // 空串
  assert_eq(parse_semver("1..2"), None) // 空段
  assert_eq(parse_semver("1.2.3-rc1"), None) // 预发布后缀
}

///|
/// is_valid_semver 与 parse_semver 判定一致。
test "is_valid_semver agrees with parse_semver" {
  assert_true(is_valid_semver("0.1.0"))
  assert_false(is_valid_semver("1.2"))
  assert_false(is_valid_semver("v1.0.0"))
}

///|
/// changelog 约定路径：src/{方向}/CHANGELOG.md。
test "default_changelog_path follows convention" {
  assert_eq(
    default_changelog_path("regex_engine"),
    "src/regex_engine/CHANGELOG.md",
  )
  assert_eq(default_changelog_path("dst"), "src/dst/CHANGELOG.md")
}
