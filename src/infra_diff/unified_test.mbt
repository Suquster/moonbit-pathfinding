// unified_test.mbt —— unified diff 输出 / 解析 / 应用测试。

///|
/// 单编辑点：hunk 头行号与 GNU diff -u 对齐。
test "format_unified single hunk matches gnu layout" {
  let old = ["a", "b", "c", "d", "e", "f", "g", "h"]
  let new = ["a", "b", "c", "d", "X", "f", "g", "h"]
  let text = format_unified(old, new)
  assert_true(text == "@@ -2,7 +2,7 @@\n b\n c\n d\n-e\n+X\n f\n g\n h\n")
}

///|
/// 相邻编辑合并为一个 hunk；远距编辑拆成多个 hunk。
test "hunk merging and splitting by context distance" {
  let old : Array[String] = []
  for i in 0..<30 {
    old.push("line" + i.to_string())
  }
  // 近距两处编辑（间隔 2 < 2×context）→ 单 hunk。
  let near : Array[String] = []
  for i in 0..<30 {
    near.push(if i == 5 || i == 8 { "EDIT" + i.to_string() } else { old[i] })
  }
  assert_true(hunks_of(diff_lines(old, near)).length() == 1)
  // 远距两处编辑（间隔 20 > 2×context）→ 两个 hunk。
  let far : Array[String] = []
  for i in 0..<30 {
    far.push(if i == 2 || i == 25 { "EDIT" + i.to_string() } else { old[i] })
  }
  assert_true(hunks_of(diff_lines(old, far)).length() == 2)
  // 无编辑 → 零 hunk、空输出。
  assert_true(hunks_of(diff_lines(old, old)).length() == 0)
  assert_true(format_unified(old, old) == "")
}

///|
/// 解析 + 应用：format → parse → apply 端到端恒等（含纯插入/纯删除/边界）。
test "parse and apply unified roundtrip" {
  let cases : Array[(Array[String], Array[String])] = [
    (["a", "b", "c"], ["a", "X", "c"]),
    (["a", "b", "c"], ["a", "b", "c", "d", "e"]), // 尾部插入
    (["a", "b", "c", "d"], ["c", "d"]), // 头部删除
    ([], ["only", "new"]), // 空 → 非空
    (["gone"], []), // 非空 → 空
  ]
  for case in cases {
    let (old, new) = case
    let text = format_unified(old, new)
    match parse_unified(text) {
      Some(hunks) =>
        match apply_unified(old, hunks) {
          Some(applied) => assert_true(applied == new)
          None => fail("apply should succeed")
        }
      None => fail("parse should succeed")
    }
  }
}

///|
/// 上下文不匹配时拒绝应用（patch reject 语义）。
test "apply_unified rejects context mismatch" {
  let old = ["a", "b", "c"]
  let new = ["a", "X", "c"]
  let text = format_unified(old, new)
  match parse_unified(text) {
    Some(hunks) => {
      // 原文被改动 → 上下文校验失败。
      assert_true(apply_unified(["a", "CHANGED", "c"], hunks) is None)
      assert_true(apply_unified([], hunks) is None)
    }
    None => fail("parse should succeed")
  }
}

///|
/// 畸形 unified 文本显式拒绝。
test "parse_unified rejects malformed input" {
  assert_true(parse_unified("@@ bogus @@\n") is None)
  assert_true(parse_unified("@@ -1,2 +1,2 @@\n a\n") is None) // 体行数不足
  assert_true(parse_unified("@@ -1,1 +1,1 @@\n?a\n") is None) // 未知前缀
  // 文件头行被忽略。
  match parse_unified("--- a.txt\n+++ b.txt\n@@ -1,1 +1,1 @@\n-x\n+y\n") {
    Some(hunks) => {
      assert_true(hunks.length() == 1)
      assert_true(apply_unified(["x"], hunks) == Some(["y"]))
    }
    None => fail("headers should be skipped")
  }
}

///|
/// PBT：随机行数组对 format→parse→apply 恒等（200 迭代）。
test "prop unified roundtrip on random line arrays" {
  let mut seed = 0x243F6A88U
  for _ in 0..<200 {
    let old : Array[String] = []
    let new : Array[String] = []
    seed = seed * 1664525U + 1013904223U
    let n = ((seed >> 8) % 20U).reinterpret_as_int()
    for i in 0..<n {
      seed = seed * 1664525U + 1013904223U
      old.push("L" + ((seed >> 8) % 5U).to_string() + "_" + i.to_string())
    }
    seed = seed * 1664525U + 1013904223U
    let m = ((seed >> 8) % 20U).reinterpret_as_int()
    for i in 0..<m {
      seed = seed * 1664525U + 1013904223U
      new.push("L" + ((seed >> 8) % 5U).to_string() + "_" + i.to_string())
    }
    let text = format_unified(old, new)
    match parse_unified(text) {
      Some(hunks) =>
        match apply_unified(old, hunks) {
          Some(applied) => assert_true(applied == new)
          None => fail("prop apply failed")
        }
      None => fail("prop parse failed")
    }
  }
}
