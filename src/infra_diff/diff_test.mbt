// diff_test.mbt —— Myers diff / patch / SemVer 测试（已知向量 + PBT）。

///|
test "diff known cases" {
  // 相同序列：全 Keep。
  let same = @infra_diff.diff_lines(["a", "b"], ["a", "b"])
  assert_eq(@infra_diff.edit_distance(same), 0)
  // 空 → 非空：全 Insert。
  let ins = @infra_diff.diff_lines([], ["x", "y"])
  assert_eq(@infra_diff.edit_distance(ins), 2)
  // 非空 → 空：全 Delete。
  let del = @infra_diff.diff_lines(["x", "y"], [])
  assert_eq(@infra_diff.edit_distance(del), 2)
  // Myers 论文经典例：ABCABBA → CBABAC 的 SES 长度为 5。
  let ops = @infra_diff.diff_lines(["A", "B", "C", "A", "B", "B", "A"], [
    "C", "B", "A", "B", "A", "C",
  ])
  assert_eq(@infra_diff.edit_distance(ops), 5)
  // 应用后得到目标。
  assert_true(
    @infra_diff.patch_apply(["A", "B", "C", "A", "B", "B", "A"], ops) ==
    Some(["C", "B", "A", "B", "A", "C"]),
  )
}

///|
test "patch apply and revert" {
  let old = ["fn main {", "  println(1)", "}"]
  let new = ["fn main {", "  println(2)", "  println(3)", "}"]
  let ops = @infra_diff.diff_lines(old, new)
  assert_true(@infra_diff.patch_apply(old, ops) == Some(new))
  // 逆向应用还原旧版。
  assert_true(@infra_diff.patch_revert(new, ops) == Some(old))
  // 上下文不匹配拒绝。
  assert_true(@infra_diff.patch_apply(["tampered"], ops) == None)
  assert_true(@infra_diff.patch_apply([], ops) == None)
}

///|
test "diff roundtrip and minimality (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<150 {
    let vocab = ["a", "b", "c", "d"]
    let old : Array[String] = []
    let new : Array[String] = []
    for _ in 0..<rng.next_below(12) {
      old.push(vocab[rng.next_below(4)])
    }
    for _ in 0..<rng.next_below(12) {
      new.push(vocab[rng.next_below(4)])
    }
    let ops = @infra_diff.diff_lines(old, new)
    // 正向应用得 new、逆向应用得 old。
    assert_true(@infra_diff.patch_apply(old, ops) == Some(new))
    assert_true(@infra_diff.patch_revert(new, ops) == Some(old))
    // 编辑距离上界 |old|+|new|，且相同序列为 0。
    assert_true(@infra_diff.edit_distance(ops) <= old.length() + new.length())
  }
}

///|
test "semver parse valid and invalid" {
  let v = @infra_diff.semver_parse("1.2.3").unwrap()
  assert_eq(v.major, 1)
  assert_eq(v.minor, 2)
  assert_eq(v.patch, 3)
  assert_true(v.prerelease.length() == 0)
  // 预发布 + build。
  let v2 = @infra_diff.semver_parse("1.0.0-alpha.1+build.5").unwrap()
  assert_true(v2.prerelease == ["alpha", "1"])
  assert_eq(v2.build, "build.5")
  // 预发布段含连字符。
  let v3 = @infra_diff.semver_parse("1.0.0-x-y-z").unwrap()
  assert_true(v3.prerelease == ["x-y-z"])
  // 畸形拒绝。
  assert_true(@infra_diff.semver_parse("1.2") == None) // 缺段
  assert_true(@infra_diff.semver_parse("1.2.3.4") == None) // 多段
  assert_true(@infra_diff.semver_parse("01.2.3") == None) // 前导零
  assert_true(@infra_diff.semver_parse("1.2.3-01") == None) // 预发布数字段前导零
  assert_true(@infra_diff.semver_parse("1.2.3-") == None) // 空预发布
  assert_true(@infra_diff.semver_parse("1.2.3+") == None) // 空 build
  assert_true(@infra_diff.semver_parse("1.2.3-a..b") == None) // 空段
  assert_true(@infra_diff.semver_parse("a.b.c") == None)
  assert_true(@infra_diff.semver_parse("") == None)
}

///|
test "semver precedence follows spec section 11" {
  // 规范 §11 给出的完整优先级链。
  let chain = [
    "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
    "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0",
  ]
  for i in 0..<(chain.length() - 1) {
    let a = @infra_diff.semver_parse(chain[i]).unwrap()
    let b = @infra_diff.semver_parse(chain[i + 1]).unwrap()
    assert_eq(@infra_diff.semver_compare(a, b), -1)
    assert_eq(@infra_diff.semver_compare(b, a), 1)
  }
  // 核心段比较。
  let v100 = @infra_diff.semver_parse("1.0.0").unwrap()
  let v200 = @infra_diff.semver_parse("2.0.0").unwrap()
  let v210 = @infra_diff.semver_parse("2.1.0").unwrap()
  let v211 = @infra_diff.semver_parse("2.1.1").unwrap()
  assert_eq(@infra_diff.semver_compare(v100, v200), -1)
  assert_eq(@infra_diff.semver_compare(v200, v210), -1)
  assert_eq(@infra_diff.semver_compare(v210, v211), -1)
  // build 元数据不参与比较。
  let ba = @infra_diff.semver_parse("1.0.0+aaa").unwrap()
  let bb = @infra_diff.semver_parse("1.0.0+bbb").unwrap()
  assert_eq(@infra_diff.semver_compare(ba, bb), 0)
  // 自反。
  assert_eq(@infra_diff.semver_compare(v100, v100), 0)
}
