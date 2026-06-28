// prop_dispatch_test.mbt —— JSON-RPC 2.0 分发正确性属性测试（任务 3.4，Property 2）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 2「分发正确性」：
//
//   *对任意* 由生成器产出的请求消息与路由表：
//     * 当 `method` 在路由表中**命中**时，`dispatch` 调用对应处理器并返回其结果
//       （与直接调用 `lookup` 取得的处理器作用于该消息的结果逐一相等）；
//     * 当 `method`**未命中**时，`dispatch` 返回携带 `method_not_found_code`
//       且 `id` 与请求 `id` 相等的错误响应
//       （`Some(error_response(id, method_not_found_code, "Method not found: " + method))`）。
//
// **Validates: Requirements 2.6, 2.7, 2.9**
//
// paper-to-code 追溯：
//   * JSON-RPC 2.0 §4.3 —— 方法不存在时返回 -32601 (Method not found) 错误；
//     §5 Response object —— 响应 `id` 必须等于触发它的请求 `id`。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（每条属性
// ≥100 次迭代，由模板默认 `iters=100` 保证）。
//
// 生成器复用：`gen_id` / `gen_json` / `gen_ascii_string` 已在同包文件
// `prop_roundtrip_test.mbt` 定义，本文件直接复用，不重复定义（同包重名会冲突）。

// ---------------------------------------------------------------------------
// 固定路由表（注册若干 method 的确定性处理器）
// ---------------------------------------------------------------------------

///|
/// 构造一个确定性路由表：注册三个请求处理器，每个处理器回显请求 `id` 并返回随
/// `method` 而定的确定性结果字符串（命中分支因此产生稳定可比较的响应）；并故意
/// 注册一个对请求返回 `None` 的处理器（处理器选择不回应），验证 `dispatch` 忠实
/// 透传处理器结果（含 `None`）。
fn pd_router() -> Router {
  let router = Router::new()
  router.register("pd/alpha", fn(msg) {
    match msg {
      Request(id~, ..) =>
        Some(
          JsonRpcMessage::Response(
            id~,
            result=Some(JStr("handled:pd/alpha")),
            error=None,
          ),
        )
      _ => None
    }
  })
  router.register("pd/beta", fn(msg) {
    match msg {
      Request(id~, ..) =>
        Some(
          JsonRpcMessage::Response(
            id~,
            result=Some(JStr("handled:pd/beta")),
            error=None,
          ),
        )
      _ => None
    }
  })
  // 处理器选择不回应：`dispatch` 应原样返回其 `None`。
  router.register("pd/silent", fn(_msg) { None })
  router
}

// ---------------------------------------------------------------------------
// 请求消息生成器（method 取自小集合 + 偶尔随机，覆盖命中/未命中）
// ---------------------------------------------------------------------------

///|
/// 生成一个请求 method 名：多数取自小集合（含已注册的 "pd/alpha"/"pd/beta"/
/// "pd/silent" 与未注册的 "pd/miss0"/"pd/miss1"，覆盖命中与未命中），偶尔（1/6
/// 概率）退化为随机 ASCII 名（几乎必为未命中），以增广未命中输入空间。
fn gen_dispatch_method(rng : @infra_pbt.Rng) -> String {
  if rng.next_below(6) == 0 {
    gen_ascii_string(rng, 6)
  } else {
    let methods = ["pd/alpha", "pd/beta", "pd/silent", "pd/miss0", "pd/miss1"]
    methods[rng.next_below(methods.length())]
  }
}

///|
/// 生成一条随机请求消息（始终为 `Request`，因 Property 2 针对请求分发）：随机
/// `Id` + 小集合/随机 `method` + 随机 `Json` params。
fn gen_dispatch_request(rng : @infra_pbt.Rng) -> JsonRpcMessage {
  JsonRpcMessage::Request(
    id=gen_id(rng),
    method_name=gen_dispatch_method(rng),
    params=gen_json(rng, 2),
  )
}

///|
/// 随机请求消息生成器（封装为 @infra_pbt.Gen）。
fn gen_dispatch_request_gen() -> @infra_pbt.Gen[JsonRpcMessage] {
  @infra_pbt.Gen::new(fn(rng) { gen_dispatch_request(rng) })
}

// ---------------------------------------------------------------------------
// 属性谓词
// ---------------------------------------------------------------------------

///|
/// 分发正确性谓词：对一条请求消息与路由表，校验 `dispatch` 的命中/未命中行为。
///
///   * 命中（`lookup(method)` 为 `Some(handler)`）：`dispatch` 结果与直接调用该
///     处理器作用于该消息的结果逐一相等（Requirement 2.6）。
///   * 未命中：`dispatch` 结果恰为
///     `Some(error_response(id, method_not_found_code, "Method not found: " + method))`，
///     其错误码为 `method_not_found_code` 且 `id` 与请求 `id` 相等
///     （Requirements 2.7, 2.9）。
fn dispatch_correct(msg : JsonRpcMessage, router : Router) -> Bool {
  match msg {
    Request(id~, method_name~, ..) =>
      match router.lookup(method_name) {
        // 命中：dispatch 必与直接调用 lookup 取得的处理器结果一致。
        Some(handler) => dispatch(msg, router) == handler(msg)
        // 未命中：dispatch 必合成 id 一致的 method_not_found 错误响应。
        None =>
          dispatch(msg, router) ==
          Some(
            error_response(
              id,
              method_not_found_code,
              "Method not found: " + method_name,
            ),
          )
      }
    // 生成器仅产出请求，其余形态视为平凡满足。
    _ => true
  }
}

// ---------------------------------------------------------------------------
// 属性测试（Property 2）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 2: 分发正确性
///
/// 对任意由生成器产出的请求消息，`dispatch` 在命中时返回对应处理器的结果、未命中
/// 时返回携带 `method_not_found_code` 且 `id` 与请求一致的错误响应。复用
/// @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（满足 ≥100 迭代
/// 基线）。
///
/// **Validates: Requirements 2.6, 2.7, 2.9**
test "Feature: lsp, Property 2: dispatch routes hits to handlers and misses to method_not_found" {
  let router = pd_router()
  let ok = @infra_pbt.holds_for_all(gen_dispatch_request_gen(), fn(msg) {
    dispatch_correct(msg, router)
  })
  assert_true(ok)
}

///|
/// Feature: lsp, Property 2: 未命中错误响应的 id 一致性（聚焦见证）
///
/// 进一步以聚焦视角校验未命中分支：构造确定未注册 method 的请求，`dispatch` 返回
/// 的错误响应其 `id` 与请求 `id` 相等且错误码为 `method_not_found_code`
/// （Requirements 2.7, 2.9）。
///
/// **Validates: Requirements 2.7, 2.9**
test "Feature: lsp, Property 2: miss response carries request id and method_not_found_code" {
  let router = pd_router()
  let gen_miss = @infra_pbt.Gen::new(fn(rng) {
    JsonRpcMessage::Request(
      id=gen_id(rng),
      method_name="pd/definitely-missing/" + gen_ascii_string(rng, 4),
      params=gen_json(rng, 1),
    )
  })
  let ok = @infra_pbt.holds_for_all(gen_miss, fn(msg) {
    match msg {
      Request(id~, ..) =>
        match dispatch(msg, router) {
          Some(Response(id=resp_id, result=None, error=Some(e))) =>
            resp_id == id && e.code == method_not_found_code
          _ => false
        }
      _ => false
    }
  })
  assert_true(ok)
}
