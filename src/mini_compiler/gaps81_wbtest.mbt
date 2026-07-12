// gaps81_wbtest.mbt —— erase_span 元组臂与 expr_span ELet 臂（第八十一批）。

///|
/// erase_span：元组表达式逐元素去 span。
test "erase_span：元组逐元素去 span" {
  let z = Span::{ line: 0, col: 0 }
  let e = ETuple(
    [EInt(1, Span::{ line: 3, col: 5 }), EBool(true, Span::{ line: 4, col: 1 })],
    Span::{ line: 3, col: 4 },
  )
  match erase_span(e) {
    ETuple(items, sp) => {
      assert_true(sp == z)
      assert_true(items[0] is EInt(1, _))
      match items[0] {
        EInt(_, s0) => assert_true(s0 == z)
        _ => fail("元素 0 应为 EInt")
      }
      match items[1] {
        EBool(_, s1) => assert_true(s1 == z)
        _ => fail("元素 1 应为 EBool")
      }
    }
    _ => fail("应保持 ETuple 构造")
  }
}

///|
/// expr_span：ELet 结点取其自身 span。
test "expr_span：ELet 取自身 span" {
  let sp = Span::{ line: 7, col: 2 }
  let e = ELet("x", EInt(1, sp), EVar("x", sp), sp)
  assert_true(expr_span(e) == sp)
}
