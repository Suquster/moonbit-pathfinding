// 黑盒测试：覆盖率审计收口（INFRA 第七十一批）——
// demo 能力路由器：通知消息无响应、缺失位置参数回退 (0,0)、
// 定义未命中返回 JSON null。

///|
fn drg_router() -> @lsp_binding.Router {
  @lsp_server.demo_capability_router("file:///demo.conf", "port = 8080")
}

///|
test "demo_capability_router：通知消息各方法均无响应" {
  let router = drg_router()
  for
    m in [
      "textDocument/diagnostic", "textDocument/completion", "textDocument/definition",
      "textDocument/references", "textDocument/rename", "textDocument/hover",
    ] {
    let note = @lsp_binding.Notification(
      method_name=m,
      params=@lsp_binding.JNull,
    )
    assert_true(@lsp_binding.dispatch(note, router) is None)
  }
}

///|
test "demo_capability_router：缺失位置参数回退 (0,0) 仍产生响应" {
  let router = drg_router()
  for
    m in [
      "textDocument/completion", "textDocument/definition", "textDocument/hover",
    ] {
    let req = @lsp_binding.Request(
      id=@lsp_binding.IdNum(1),
      method_name=m,
      params=@lsp_binding.JNull,
    )
    assert_true(
      @lsp_binding.dispatch(req, router) is Some(@lsp_binding.Response(..)),
    )
  }
}

///|
test "demo_capability_router：定义未命中返回 JSON null" {
  let router = drg_router()
  let req = @lsp_binding.Request(
    id=@lsp_binding.IdNum(2),
    method_name="textDocument/definition",
    params=@lsp_binding.JObj([
      ("line", @lsp_binding.JNum("5")),
      ("character", @lsp_binding.JNum("0")),
    ]),
  )
  match @lsp_binding.dispatch(req, router) {
    Some(@lsp_binding.Response(result~, ..)) =>
      assert_true(result is Some(@lsp_binding.JNull))
    _ => assert_true(false)
  }
}
