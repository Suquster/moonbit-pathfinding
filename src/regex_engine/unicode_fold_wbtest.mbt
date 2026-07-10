// unicode_fold_wbtest.mbt —— 折叠表内部不变量（白盒）。

///|
test "Unicode 折叠：CharSet::case_fold 超集与幂等" {
  // 超集不变量：折叠结果包含原集合。
  let base = char_set_of_char('é')
  let folded = base.case_fold()
  assert_true(folded.contains(0xE9))
  assert_true(folded.contains(0xC9))
  // 幂等：轨道闭包再折叠不再扩大。
  let twice = folded.case_fold()
  assert_true(twice == folded)
  // 三元轨道闭包：从任一成员出发得到全轨道。
  let sig = char_set_of_char('ς').case_fold()
  assert_true(sig.contains(0x3C3))
  assert_true(sig.contains(0x3A3))
  assert_true(sig.contains(0x3C2))
}
