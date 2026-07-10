// unified_gaps_test.mbt —— unified diff 解析/应用防御分支收口
// （INFRA 第三十一批）：畸形 hunk 头、无尾换行文本、空体行、重叠 hunk 拒绝。

///|
test "parse_unified：畸形 hunk 头逐段拒绝" {
  // '-' 后非数字 → 行号解析失败。
  assert_true(@infra_diff.parse_unified("@@ -x +1 @@\n") is None)
  // 缺 " +" 段。
  assert_true(@infra_diff.parse_unified("@@ -1,2 @@\n") is None)
  // 缺尾部 " @@"。
  assert_true(@infra_diff.parse_unified("@@ -1,2 +3,4\n") is None)
}

///|
test "parse_unified：无尾换行文本与空体行容错" {
  // 无尾换行：最后一行仍被收集。
  let txt = "@@ -1,2 +1,2 @@\n a\n-b\n+B"
  match @infra_diff.parse_unified(txt) {
    Some(hunks) => {
      assert_eq(hunks.length(), 1)
      assert_eq(hunks[0].lines.length(), 3)
    }
    None => assert_true(false)
  }
  // 空行按空上下文行（Keep("")）处理。
  let txt2 = "@@ -1,2 +1,2 @@\n\n-b\n+B\n"
  match @infra_diff.parse_unified(txt2) {
    Some(hunks) => assert_true(hunks[0].lines[0] is Keep(""))
    None => assert_true(false)
  }
}

///|
test "apply_unified：重叠/越界 hunk 拒绝" {
  let old = ["a", "b", "c"]
  match
    @infra_diff.parse_unified(
      "@@ -1,2 +1,2 @@\n a\n-b\n+B\n@@ -1,2 +1,2 @@\n a\n-b\n+B\n",
    ) {
    Some(hunks) => assert_true(@infra_diff.apply_unified(old, hunks) is None)
    None => assert_true(false)
  }
  match @infra_diff.parse_unified("@@ -9,1 +9,1 @@\n-z\n+Z\n") {
    Some(hunks) => assert_true(@infra_diff.apply_unified(old, hunks) is None)
    None => assert_true(false)
  }
}
