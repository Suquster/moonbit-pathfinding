// prop_batch_test.mbt —— JSON-RPC 2.0 批量逐条处理属性测试（任务 2.3，Property 3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 3「批量逐条处理」：
//
//   *对任意* 由生成器产出的 请求/通知/响应 序列与一个路由表，批量分发
//   `dispatch_batch(msgs, router)` 所得响应数组，与对各元素**逐条** `dispatch`
//   所得响应（略去返回 `None` 的项——通知/响应/选择不回应的处理器）按序一一相等。
//
// **Validates: Requirements 2.4, 2.10**
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（每条属性
// ≥100 次迭代，由模板默认 `iters=100` 保证）。
//
// 生成器复用：单消息所依赖的 `gen_id` / `gen_json` / `gen_ascii_string` 已在同包
// 文件 `prop_roundtrip_test.mbt` 定义，本文件直接复用，不重复定义（同包重名会
// 冲突）。但既有 `gen_message` 的 method 取自随机 ASCII，与路由表注册名几乎无
// 交集；为覆盖「命中 / 未命中 / 通知」三类，本文件定义一个**小方法集 + 偶尔随机**
// 的批量消息生成器 `gen_batch_message`，使生成的消息 method 与下面 `pb_router`
// 注册的方法名有充分交集。

// ---------------------------------------------------------------------------
// 固定路由表（注册若干 method 的处理器，返回基于请求 id 的确定性响应）
// ---------------------------------------------------------------------------

///|
/// 构造一个确定性路由表：注册三个请求处理器（"m0"/"m1"/"m2"）与一个通知处理器
/// （"note"）。请求处理器回显请求 id、并返回随 method 而定的确定性结果字符串，
/// 从而让命中分支产生稳定可比较的响应；通知处理器返回 `None`（通知无响应）。
fn pb_router() -> Router {
  let router = Router::new()
  router.register("m0", fn(msg) {
    match msg {
      Request(id~, ..) =>
        Some(JsonRpcMessage::Response(id~, result=Some(JStr("r0")), error=None))
      _ => None
    }
  })
  router.register("m1", fn(msg) {
    match msg {
      Request(id~, ..) =>
        Some(JsonRpcMessage::Response(id~, result=Some(JStr("r1")), error=None))
      _ => None
    }
  })
  // 故意注册一个对请求返回 None 的处理器（处理器选择不回应），验证此类项也被略去。
  router.register("m2", fn(_msg) { None })
  // 通知处理器：注册但返回 None（通知无响应）。
  router.register("note", fn(_msg) { None })
  router
}

// ---------------------------------------------------------------------------
// 批量消息序列生成器（method 取自小集合 + 偶尔随机，覆盖命中/未命中/通知）
// ---------------------------------------------------------------------------

///|
/// 生成一个批量消息的 method 名：多数取自小集合（含已注册的 "m0"/"m1"/"m2"/
/// "note" 与未注册的 "miss0"/"miss1"，覆盖命中与未命中），偶尔（1/6 概率）退化为
/// 随机 ASCII 名（几乎必为未命中），以增广未命中输入空间。
fn gen_batch_method(rng : @infra_pbt.Rng) -> String {
  if rng.next_below(6) == 0 {
    gen_ascii_string(rng, 6)
  } else {
    let methods = ["m0", "m1", "m2", "note", "miss0", "miss1"]
    methods[rng.next_below(methods.length())]
  }
}

///|
/// 生成一条随机批量消息，覆盖三类形态：
///   * Request      —— 随机 id + 小集合/随机 method（命中则得处理器结果，未命中
///     则得 method_not_found_code 错误响应，二者均产生 `Some`）；
///   * Notification —— 小集合/随机 method（`dispatch` 恒返回 `None`，被略去）；
///   * Response     —— `dispatch` 对响应恒返回 `None`，被略去。
fn gen_batch_message(rng : @infra_pbt.Rng) -> JsonRpcMessage {
  match rng.next_below(3) {
    0 =>
      JsonRpcMessage::Request(
        id=gen_id(rng),
        method=gen_batch_method(rng),
        params=gen_json(rng, 2),
      )
    1 =>
      JsonRpcMessage::Notification(
        method=gen_batch_method(rng),
        params=gen_json(rng, 2),
      )
    _ =>
      // 响应：result 与 error 恰含其一（合法形态，便于生成器一致）。
      if rng.next_bool() {
        JsonRpcMessage::Response(
          id=gen_id(rng),
          result=Some(gen_json(rng, 1)),
          error=None,
        )
      } else {
        JsonRpcMessage::Response(
          id=gen_id(rng),
          result=None,
          error=Some(
            RpcError::new(invalid_params_code, gen_ascii_string(rng, 5)),
          ),
        )
      }
  }
}

///|
/// 生成一个随机长度（0..7）的批量消息序列。长度上界刻意保持较小以保证规模有界、
/// 迭代高效。
fn gen_batch_seq(rng : @infra_pbt.Rng) -> Array[JsonRpcMessage] {
  let n = rng.next_below(8)
  let msgs : Array[JsonRpcMessage] = []
  let mut i = 0
  while i < n {
    msgs.push(gen_batch_message(rng))
    i = i + 1
  }
  msgs
}

///|
/// 随机批量消息序列生成器（封装为 @infra_pbt.Gen）。
fn gen_batch_sequence() -> @infra_pbt.Gen[Array[JsonRpcMessage]] {
  @infra_pbt.Gen::new(fn(rng) { gen_batch_seq(rng) })
}

///|
/// 对一批消息逐条 `dispatch` 并按序收集所有 `Some` 结果（参照实现，等价于
/// `msgs.filter_map(m => dispatch(m, router))`）。
fn manual_dispatch(
  msgs : Array[JsonRpcMessage],
  router : Router,
) -> Array[JsonRpcMessage] {
  let out : Array[JsonRpcMessage] = []
  for m in msgs {
    match dispatch(m, router) {
      Some(resp) => out.push(resp)
      None => ()
    }
  }
  out
}

// ---------------------------------------------------------------------------
// 属性测试（Property 3）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 3: 批量逐条处理
///
/// 对任意由生成器产出的 请求/通知/响应 序列，`dispatch_batch(msgs, router)` 所得
/// 响应数组与对各元素逐条 `dispatch` 收集 `Some`（略去通知/响应/不回应项）所得
/// 数组按序逐条相等。复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代
/// 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 2.4, 2.10**
test "Feature: lsp, Property 3: dispatch_batch equals per-element dispatch in order" {
  let router = pb_router()
  let ok = @infra_pbt.holds_for_all(gen_batch_sequence(), fn(msgs) {
    dispatch_batch(msgs, router) == manual_dispatch(msgs, router)
  })
  assert_true(ok)
}
