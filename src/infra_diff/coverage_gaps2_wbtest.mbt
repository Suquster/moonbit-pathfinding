// 白盒测试：DiffOp/SemVer Show 渲染、patch_apply 负例、hunks 前导删除。

///|
test "diff：DiffOp Show 三分支渲染" {
  let k = DiffOp::Keep("a")
  let d = DiffOp::Delete("b")
  let i = DiffOp::Insert("c")
  assert_eq("\{k}", "  a")
  assert_eq("\{d}", "- b")
  assert_eq("\{i}", "+ c")
}

///|
test "diff：patch_apply 删除失配与残留旧行拒绝" {
  assert_true(patch_apply(["x"], [Delete("y")]) is None)
  assert_true(patch_apply(["x", "y"], [Keep("x")]) is None)
  guard patch_apply(["x", "y"], [Keep("x"), Delete("y"), Insert("z")])
    is Some(out)
  assert_eq(out, ["x", "z"])
}

///|
test "semver：Show 含预发布多段与 build 元数据" {
  let v : SemVer = {
    major: 1,
    minor: 2,
    patch: 3,
    prerelease: ["rc", "1"],
    build: "abc",
  }
  assert_eq("\{v}", "1.2.3-rc.1+abc")
}

///|
test "unified：上下文窗口外的删除行推进旧行号" {
  let ops : Array[DiffOp] = [
    Delete("d0"),
    Keep("k1"),
    Keep("k2"),
    Keep("k3"),
    Keep("k4"),
    Keep("k5"),
    Delete("d6"),
  ]
  let hs = hunks_of(ops, context=1)
  assert_true(hs.length() >= 2)
}
