// skiplist_gaps_test.mbt —— 跳表 contains 委托收口
// （INFRA 第四十四批）。

///|
test "SkipList::contains：存在与缺失双向判定" {
  let sl : @infra_ds.SkipList[Int, Int] = @infra_ds.SkipList::new()
  sl.insert(1, 10) |> ignore
  sl.insert(2, 20) |> ignore
  assert_true(sl.contains(1))
  assert_false(sl.contains(3))
}
