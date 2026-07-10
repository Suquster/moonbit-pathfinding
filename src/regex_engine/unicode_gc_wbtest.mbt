// unicode_gc_wbtest.mbt —— 包内不变量：`Cn`（未分配）无登记区间表，
// 其集合以补集构造（见 category_charset）。

///|
test "gc_table_of(Cn) 为空表（Cn 以补集构造）" {
  assert_eq(gc_table_of(Cn).length(), 0)
  assert_false(gc_table_contains(gc_table_of(Cn), 0x0378))
}
