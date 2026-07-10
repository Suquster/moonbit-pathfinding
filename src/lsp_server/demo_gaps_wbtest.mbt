// demo_gaps_wbtest.mbt —— demo 回复投影空值回退分支收口
// （INFRA 第四十一批）。

///|
test "demo_result_of：result/error 皆缺省回退 JNull 与错误投影" {
  // 无回复。
  assert_true(demo_result_of(None) is @lsp_binding.JNull)
  // result=None 且 error=None → JNull。
  let empty = @lsp_binding.Response(
    id=@lsp_binding.IdNum(1),
    result=None,
    error=None,
  )
  assert_true(demo_result_of(Some(empty)) is @lsp_binding.JNull)
  // error 投影为 {"error": message}。
  let err = @lsp_binding.Response(
    id=@lsp_binding.IdNum(2),
    result=None,
    error=Some(@lsp_binding.RpcError::new(-1, "boom")),
  )
  match demo_result_of(Some(err)) {
    @lsp_binding.JObj(fields) => assert_true(fields[0].0 == "error")
    _ => assert_true(false)
  }
}
