// gaps83_test.mbt —— expr_span ELetRec 臂（第八十三批）。

///|
/// expr_span：ELetRec 取自身 span。
test "expr_span：ELetRec 取自身 span" {
  let sp = Span::{ line: 9, col: 3 }
  let e = ELetRec("f", ELam("x", EVar("x", sp), sp), EVar("f", sp), sp)
  assert_true(expr_span(e) == sp)
}

///|
/// expr_span：ETuple 取自身 span。
test "expr_span：ETuple 取自身 span" {
  let sp = Span::{ line: 2, col: 8 }
  let z = Span::{ line: 0, col: 0 }
  let e = ETuple([EInt(1, z), EInt(2, z)], sp)
  assert_true(expr_span(e) == sp)
}
