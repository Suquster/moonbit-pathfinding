// exhaustive_gaps_wbtest.mbt —— Maranget 穷尽性内部算子收口
// （INFRA 第二十三批）：通配特化展开、见证重建、缺失整数字面量。

///|
test "specialize_row：通配首模式按元数展开等量通配" {
  match specialize_row(CTuple(2), 2, [PWild, PInt(9)]) {
    Some(out) => {
      assert_eq(out.length(), 3)
      assert_true(out[0] is PWild)
      assert_true(out[1] is PWild)
      assert_true(out[2] is PInt(9))
    }
    None => assert_true(false)
  }
}

///|
test "rebuild_witness：整数构造子重建 PInt 头" {
  let (head, rest) = rebuild_witness(CInt(7), 0, [PBool(true)])
  assert_true(head is PInt(7))
  assert_eq(rest.length(), 1)
}

///|
test "fresh_int_not_in：跳过既有字面量并忽略非整数头" {
  let p = fresh_int_not_in([PInt(0), PInt(1), PWild, PBool(true)])
  assert_true(p is PInt(2))
}
