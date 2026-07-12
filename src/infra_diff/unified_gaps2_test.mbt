// 黑盒测试：覆盖率审计收口（INFRA 第七十六批）——
// 补丁应用的前导/尾随未变段拷贝与三方合并区间间隙拷贝。

///|
fn ug2_lines(prefix : String, n : Int) -> Array[String] {
  let out : Array[String] = []
  for i in 0..<n {
    out.push(prefix + i.to_string())
  }
  out
}

///|
test "apply_unified：中段修改时前导与尾随行原样拷贝" {
  let old = ug2_lines("l", 20)
  let new_ : Array[String] = []
  for i in 0..<20 {
    new_.push(if i == 10 { "changed" } else { "l" + i.to_string() })
  }
  let ops = @infra_diff.diff_lines(old, new_)
  let hunks = @infra_diff.hunks_of(ops, context=1)
  guard @infra_diff.apply_unified(old, hunks) is Some(applied)
  assert_true(applied == new_)
}

///|
test "diff3_merge：两处相距较远的单侧修改经间隙拷贝合并" {
  let base = ug2_lines("b", 30)
  let ours : Array[String] = []
  let theirs : Array[String] = []
  for i in 0..<30 {
    ours.push(if i == 2 { "ours" } else { "b" + i.to_string() })
    theirs.push(if i == 27 { "theirs" } else { "b" + i.to_string() })
  }
  let chunks = @infra_diff.diff3_merge(base, ours, theirs)
  let (merged, conflict) = @infra_diff.render_merge(chunks)
  assert_false(conflict)
  assert_eq(merged[2], "ours")
  assert_eq(merged[27], "theirs")
}
