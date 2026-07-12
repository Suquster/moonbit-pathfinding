// rope_sync_gaps_wbtest.mbt —— join 平衡修复（joinLeft 双旋/直返）收口
// （INFRA 第二十九批）。

///|
fn rs_leaf(n : Int) -> Rope {
  RLeaf(Array::make(n, 97))
}

///|
test "rope_join_left：t 过高触发左旋后整体右旋" {
  // r = (rl, rr)：rl 高 2、rr 高 1；l 高 1 → t = mk(l, rl) 高 3 > rr 高 + 1。
  let rl = rope_mk(rs_leaf(1), rs_leaf(1))
  let r = rope_mk(rl, rs_leaf(1))
  let out = rope_join_left(rs_leaf(1), r)
  assert_eq(out.cp_len(), 4)
  assert_true(out.height() <= 3)
}

///|
test "rope_join_left：递归下降后 t 不超高直接返回" {
  // rl 高 3（> l 高 + 1 触发递归），rr 高 3 → 回溯时 t 高 ≤ rr 高 + 1 直返。
  let h2a = rope_mk(rs_leaf(1), rs_leaf(1))
  let h2b = rope_mk(rs_leaf(1), rs_leaf(1))
  let h2c = rope_mk(rs_leaf(1), rs_leaf(1))
  let h2d = rope_mk(rs_leaf(1), rs_leaf(1))
  let rl = rope_mk(h2a, h2b)
  let rr = rope_mk(h2c, h2d)
  let r = rope_mk(rl, rr)
  let out = rope_join_left(rs_leaf(1), r)
  assert_eq(out.cp_len(), 9)
  assert_true(out.height() <= 5)
}

///|
test "rope_join_right：递归下降后回溯左旋修复" {
  // ll 浅、lr 深：递归 join 后 t 超高触发左旋分支。
  let h2a = rope_mk(rs_leaf(1), rs_leaf(1))
  let h2b = rope_mk(rs_leaf(1), rs_leaf(1))
  let lr = rope_mk(h2a, h2b)
  let l = rope_mk(rs_leaf(1), lr)
  let out = rope_join_right(l, rs_leaf(1))
  assert_eq(out.cp_len(), 6)
  assert_true(out.height() <= 4)
}

///|
test "rope_join：右侧显著更高走 join_left 路径" {
  let h2a = rope_mk(rs_leaf(1), rs_leaf(1))
  let h2b = rope_mk(rs_leaf(1), rs_leaf(1))
  let r = rope_mk(h2a, h2b)
  let out = rope_join(rs_leaf(1), r)
  assert_eq(out.cp_len(), 5)
}

///|
test "nth_newline：叶内换行数不足时返回叶长" {
  let leaf = rs_leaf(3) // 无换行。
  assert_eq(leaf.nth_newline(0), 3)
}

///|
test "position_to_index：负行/负列直接拒绝" {
  let doc = RopeDocument::from_string("ab\ncd")
  assert_true(doc.position_to_index({ line: -1, character: 0 }, Utf16) is None)
  assert_true(doc.position_to_index({ line: 0, character: -1 }, Utf16) is None)
}
