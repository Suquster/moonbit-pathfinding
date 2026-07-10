// semver_gaps_test.mbt —— semver 解析防御分支收口
// （INFRA 第三十八批）：多 '+'、空数字段、非数字 minor/patch、
// 预发布段非法字符。

///|
test "semver_parse：多 build 元数据与空数字段拒绝" {
  assert_true(@infra_diff.semver_parse("1.2.3+a+b") is None)
  assert_true(@infra_diff.semver_parse("1..3") is None)
}

///|
test "semver_parse：非数字 minor/patch 拒绝" {
  assert_true(@infra_diff.semver_parse("1.x.3") is None)
  assert_true(@infra_diff.semver_parse("1.2.x") is None)
}

///|
test "semver_parse：预发布段非法字符拒绝" {
  assert_true(@infra_diff.semver_parse("1.2.3-a_b") is None)
  assert_true(@infra_diff.semver_parse("1.2.3-ok.2") is Some(_))
}
