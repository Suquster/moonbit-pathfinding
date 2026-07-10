// lifecycle_gaps_test.mbt —— 生命周期消息分类/参数解析防御分支收口
// （INFRA 第三十五批）。

///|
test "LifecycleState：Show 全构造输出" {
  assert_eq("\{@lsp_server.Uninitialized}", "Uninitialized")
  assert_eq("\{@lsp_server.Initializing}", "Initializing")
  assert_eq("\{@lsp_server.Initialized}", "Initialized")
  assert_eq("\{@lsp_server.ShuttingDown}", "ShuttingDown")
}

///|
test "LspSession::handle：一般请求/通知/响应消息分类" {
  let sess = @lsp_server.LspSession::new()
  // 未初始化时的一般请求（既非 initialize 也非 shutdown）。
  let _ = sess.handle(
    @lsp_binding.Request(
      id=@lsp_binding.IdNum(1),
      method_name="textDocument/hover",
      params=@lsp_binding.JNull,
    ),
  )
  // 一般通知（既非 initialized 也非 exit）。
  let _ = sess.handle(
    @lsp_binding.Notification(
      method_name="$/cancelRequest",
      params=@lsp_binding.JNull,
    ),
  )
  // 响应消息不驱动生命周期。
  let before = sess.state()
  let _ = sess.handle(
    @lsp_binding.Response(
      id=@lsp_binding.IdNum(9),
      result=Some(@lsp_binding.JNull),
      error=None,
    ),
  )
  assert_true(sess.state() == before)
}

///|
test "initialize：capabilities 字段混杂/非数组容错" {
  let sess = @lsp_server.LspSession::new()
  // capabilities 数组含非字符串项 + positionEncodings 非数组 → 均安全忽略。
  let params = @lsp_binding.JObj([
    (
      "capabilities",
      @lsp_binding.JArr([@lsp_binding.JStr("hover"), @lsp_binding.JNum("1")]),
    ),
    ("positionEncodings", @lsp_binding.JStr("utf-16")),
  ])
  let (next, _) = sess.handle(
    @lsp_binding.Request(
      id=@lsp_binding.IdNum(1),
      method_name="initialize",
      params~,
    ),
  )
  assert_true(next.state() == @lsp_server.Initializing)
}
