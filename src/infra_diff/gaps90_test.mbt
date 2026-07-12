// gaps90_test.mbt —— SemVer 预发布比较余臂（第九十批）。

///|
/// 字母段互为前缀时短者优先级低（SemVer §11：较短集合优先级低）。
test "semver_compare：预发布字母段前缀关系" {
  match (semver_parse("1.0.0-alpha"), semver_parse("1.0.0-alphab")) {
    (Some(a), Some(b)) => {
      assert_eq(semver_compare(a, b), -1)
      assert_eq(semver_compare(b, a), 1)
    }
    _ => fail("合法版本不应解析失败")
  }
}
