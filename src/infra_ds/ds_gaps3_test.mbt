// 黑盒测试：覆盖率审计收口（INFRA 第七十五批）——
// BTreeMap 深树删除借位/前后继下潜与 contains；Roaring 位图容器
// 交并的稀疏化转换与克隆。

///|
test "BTreeMap：深树全量删除触发借位与前后继下潜" {
  let m : @infra_ds.BTreeMap[Int, Int] = @infra_ds.BTreeMap::new()
  for i in 0..<500 {
    let _ = m.insert(i, i * 2)
  }
  assert_true(m.contains(250))
  assert_false(m.contains(1000))
  // 自中间键起交替删除，迫使内部节点走前驱/后继替换与借位。
  for i in 0..<500 {
    let k = if i % 2 == 0 { 250 + i / 2 } else { 249 - i / 2 }
    assert_true(m.remove(k) is Some(_))
  }
  assert_eq(m.size(), 0)
}

///|
fn rg3_dense_even() -> @infra_ds.RoaringBitmap {
  let b = @infra_ds.RoaringBitmap::new()
  for i in 0..<5000 {
    let _ = b.add(i * 2)
  }
  b
}

///|
test "RoaringBitmap：位图容器交集稀疏化与空交集" {
  let dense2 = @infra_ds.RoaringBitmap::new()
  for i in 0..<5000 {
    let _ = dense2.add(i * 2 + 1)
  }
  // 两个位图容器交集为空。
  assert_eq(rg3_dense_even().intersect_with(dense2).cardinality(), 0)
  // 位图 ∩ 位图 → 少量重叠 → 结果转数组容器。
  let dense3 = @infra_ds.RoaringBitmap::new()
  for i in 0..<5000 {
    let _ = dense3.add(i * 2 + (if i < 3 { 0 } else { 1 }))
  }
  assert_eq(rg3_dense_even().intersect_with(dense3).cardinality(), 3)
  // 数组 ∩ 位图 → 空 → 容器删除。
  let sparse = @infra_ds.RoaringBitmap::new()
  let _ = sparse.add(1)
  let _ = sparse.add(3)
  assert_eq(sparse.intersect_with(rg3_dense_even()).cardinality(), 0)
}
