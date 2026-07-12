// gaps82_test.mbt —— let rec 非函数体退化绑定（第八十二批）。

///|
/// `let rec x = 5 in x`：递归绑定体非函数抽象时退化为普通绑定（R5.6 边界）。
test "eval_ml：let rec 非函数体退化为普通绑定" {
  assert_true(eval_ml(bv_te("let rec x = 5 in x + 1")) == VInt(6))
}
