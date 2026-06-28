# lsp_binding · 可执行文档

> **方向五（LSP_Binding）** — JSON-RPC 2.0 协议层：`Content-Length` 头部帧编解码 ·
> 批量请求 · 请求取消 · 单条/批量分发 · 请求—响应 id 关联 · 三后端一致。
>
> 本文件既是 `lsp_binding` 子包的协议层使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/lsp_binding/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败（对应 **R11.4**）。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）**、tasks.md **任务 18.3**。

本文件作为 `lsp_binding` 包的黑盒测试运行：可直接调用本包公开 API
（`encode_message` / `decode_message` / `dispatch`、`encode_framed` /
`decode_framed` / `FrameReader`、`decode_batch` / `dispatch_batch` /
`encode_batch`、`CancelRegistry` / `cancel_id_of` / `cancelled_response`、
`id_of` / `correlate`、`Router`、`JsonRpcMessage`、`Json`、`Id`、错误码常量
等）而无需限定包名；本包公开的 `pub(all)` 枚举构造子（`Request` / `Response` /
`Notification`、`JObj` / `JStr` / `JNum` / `JNull`、`IdNum` / `IdStr` / `IdNull`）
亦可直接使用。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit
> toolchain 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于
> 声明一个独立条目。
>
> **关于保留字 `method_name`**：`JsonRpcMessage` 的 `method_name~` 为带标签字段，构造与
> 解构时统一使用标签形式（`method_name=...` / `method_name~`），避免与保留字冲突。

---

## paper-to-code 追溯（R8.1 / R8.2）

- **JSON-RPC 2.0 规范**：请求（Request）/ 响应（Response）/ 通知（Notification）
  三类消息、顶层数组的**批量（Batch，§6）**、五个标准错误码
  （`-32700` ParseError / `-32600` InvalidRequest / `-32601` MethodNotFound /
  `-32602` InvalidParams / `-32603` InternalError）、以及响应 `id` 必与请求 `id`
  相等的**关联规则（§5）**——分别由 `decode_message`/`encode_message`、
  `decode_batch`/`dispatch_batch`/`encode_batch`、错误码常量与 `correlate` 承载。
- **LSP Base Protocol（Header Part / Content Part）**：每条消息前置由
  `Name: Value\r\n` 行组成、以空行 `\r\n` 结束的头部块，其中 `Content-Length`
  （以字节计的正文长度）为**必需**字段，随后接 JSON-RPC 正文——由
  `encode_framed` / `decode_framed` / `FrameReader` 承载。
- **LSP 取消语义**：`$/cancelRequest` 通知携带待取消请求 `id`，服务端令该进行中
  请求以错误码 `RequestCancelled = -32800` 收场——由 `cancel_id_of` /
  `CancelRegistry` / `cancelled_response` 与 `request_cancelled_code` 承载。

---

## 开源对标（R8.4）：传输与帧处理

| 维度 | 本库（lsp_binding） | vscode-languageserver-node | tower-lsp |
|---|---|---|---|
| 帧切分 | 纯函数 `FrameReader`（字节缓冲 ⇄ 消息），无 IO | `StreamMessageReader` 读 stdio/IPC 流 | 基于 tokio 的 `Framed` 编解码器 |
| 运行时 | 无：以「字节 → 消息」纯函数表达 | Node 事件循环 + 异步读写 | tokio 异步运行时 + 任务调度 |
| 批量 | `decode_batch` 逐元素隔离解码 | 框架内处理 | 由 service 层处理 |
| 取消 | 协作式纯数据模型（取消登记表 + 取消响应） | `CancellationToken` + 真实中断 | `CancellationToken`（tokio） |
| 正文编解码 | 包内最小 `Json` 值模型，逐字节 ASCII | JSON.parse / stringify | serde_json |

## 实现边界（R8.5）

本协议层**刻意停留在「消息与字节模型层」**：

- **纯函数式帧切分，无真实 IO 运行时**：`encode_framed` / `decode_framed` /
  `FrameReader` 只做「字节缓冲 ⇄ 消息」的切分与拼装，不实现真实
  stdio / socket / pipe 收发，也不绑定任何异步事件循环。
- **取消为协作式语义模型**：`CancelRegistry` 以「取消登记表 + 进行中请求标记」的
  纯数据模型表达取消「应当」发生的结果（合成取消错误响应），不抢占式中断真实线程。
- **既有裸 JSON 行为不变**：`decode_message` / `encode_message` 继续按「无头部帧的
  裸 JSON 正文」工作；头部帧、批量为旁路新增，与既有单条接口正交。

---

## 测试夹具：字节 ⇄ 文本转换

JSON-RPC 报文与 LSP 帧均以 `Bytes` 在传输层流动。下面的辅助函数在文本与字节、
以及字节切片之间做逐字节（ASCII 无损）处理，与 `lsp_binding` 内部约定一致——
JSON-RPC 与帧的控制结构均为 ASCII。

```mbt check
///|
/// 文本 → 字节：逐字符写出低 8 位（ASCII 无损）。
fn to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 字节 → 文本：逐字节还原为字符（ASCII 无损），与 to_bytes 互逆。
fn from_bytes(b : Bytes) -> String {
  let mut s = ""
  let mut i = 0
  while i < b.length() {
    s = s + b[i].to_int().unsafe_to_char().to_string()
    i = i + 1
  }
  s
}

///|
/// 取字节切片 [start, end) 为新的 Bytes（纯函数，不改入参）。
fn slice_bytes(b : Bytes, start : Int, end : Int) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = start
  while i < end {
    arr.push(b[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
/// 顺序拼接两段 Bytes（纯函数，返回新 Bytes）。
fn cat_bytes(a : Bytes, b : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < a.length() {
    arr.push(a[i])
    i = i + 1
  }
  i = 0
  while i < b.length() {
    arr.push(b[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}
```

---

## 示例 1 · 头部帧编解码往返（encode_framed / decode_framed）

LSP Base Protocol 约定每条消息前置 `Content-Length: <正文字节数>\r\n\r\n` 头部，
随后接 JSON-RPC 正文（**R2.1 / R2.2**）。`encode_framed` 在既有 `encode_message`
正文之上拼出头部；`decode_framed` 按头部声明的字节数切出正文再交既有
`decode_message` 解码，故 `decode_framed(encode_framed(m)) == m`。

```mbt check
///|
test "README · 头部帧编解码往返" {
  // 一条 initialize 请求消息。
  let msg = JsonRpcMessage::Request(
    id=Id::IdNum(1),
    method_name="initialize",
    params=Json::JObj([("rootUri", Json::JStr("file:///proj"))]),
  )

  // 带帧编码：Content-Length 头部 + 裸 JSON 正文。
  let framed = encode_framed(msg)
  let text = from_bytes(framed)

  // 头部以 "Content-Length: " 起始，并以空行 \r\n\r\n 与正文分隔。
  assert_true(text.length() > 18)
  let header_prefix = from_bytes(slice_bytes(framed, 0, 16))
  @test.assert_eq(header_prefix, "Content-Length: ")

  // 声明的字节数应等于裸 JSON 正文（encode_message）的字节数。
  let body = encode_message(msg)
  let expected_header = "Content-Length: " +
    body.length().to_string() +
    "\r\n\r\n"
  @test.assert_eq(
    framed.length(),
    to_bytes(expected_header).length() + body.length(),
  )

  // 解码单帧应得到与原消息逐字段相等的结果。
  match decode_framed(framed) {
    Ok(decoded) => @test.assert_eq(decoded, msg)
    Err(e) => fail("解码应成功，却得到错误：" + e.message)
  }
}
```

---

## 示例 2 · 流式多帧切分（FrameReader）

字节流中可能一次到达半条帧、或一次到达多条帧。`FrameReader` 在累积缓冲上
**纯函数式**反复切出完整帧：数据不足时 `next` 返回 `Ok(None)`（缓冲保持可继续），
切出一帧时返回 `Ok(Some((msg, rest)))`，其中 `rest` 是消费该帧后的新读取器
（**R2.2 / Property 12**）。

```mbt check
///|
test "README · FrameReader 逐条切出连续多帧" {
  let m1 = JsonRpcMessage::Request(
    id=Id::IdStr("a"),
    method_name="ping",
    params=Json::JNull,
  )
  let m2 = JsonRpcMessage::Notification(
    method_name="note",
    params=Json::JObj([("n", Json::JNum("1"))]),
  )

  // 两条消息依次写帧后拼接成一段字节流。
  let stream = cat_bytes(encode_framed(m1), encode_framed(m2))

  // 先只投喂前 5 个字节（"Conte"）—— 头部尚未终止，应数据不足。
  let r0 = FrameReader::new().push(slice_bytes(stream, 0, 5))
  match r0.next() {
    Ok(None) => () // 期望：数据不足，等待更多字节。
    Ok(Some(_)) => fail("头部未终止时不应切出帧")
    Err(e) => fail("数据不足应为 Ok(None) 而非错误：" + e.message)
  }

  // 投喂剩余字节，逐条切出 m1、m2，顺序与写入序相同。
  let r1 = r0.push(slice_bytes(stream, 5, stream.length()))
  let (got1, r2) = match r1.next() {
    Ok(Some(pair)) => pair
    Ok(None) => fail("应切出第一条帧")
    Err(e) => fail("第一帧解码失败：" + e.message)
  }
  @test.assert_eq(got1, m1)
  let (got2, r3) = match r2.next() {
    Ok(Some(pair)) => pair
    Ok(None) => fail("应切出第二条帧")
    Err(e) => fail("第二帧解码失败：" + e.message)
  }
  @test.assert_eq(got2, m2)

  // 全部帧消费完毕，缓冲为空 → Ok(None)。
  match r3.next() {
    Ok(None) => ()
    _ => fail("缓冲耗尽后应为 Ok(None)")
  }
}
```

---

## 示例 3 · 畸形帧返回规范错误（不终止进程）

缺 `Content-Length`、其值非非负整数或正文长度不足时，`decode_framed` 返回携带
`parse_error_code` 的结构化错误，绝不 panic/abort，也不产出半成品消息
（**R2.3 / R11.3**）。

```mbt check
///|
test "README · 畸形帧返回 parse_error_code" {
  // 缺少 Content-Length 头部。
  let no_len = to_bytes("Content-Type: x\r\n\r\n{}")
  match decode_framed(no_len) {
    Err(e) => @test.assert_eq(e.code, parse_error_code)
    Ok(_) => fail("缺 Content-Length 应失败")
  }

  // Content-Length 值非非负整数。
  let bad_len = to_bytes("Content-Length: abc\r\n\r\n{}")
  match decode_framed(bad_len) {
    Err(e) => @test.assert_eq(e.code, parse_error_code)
    Ok(_) => fail("非法长度应失败")
  }

  // 头部声明 100 字节正文，但实际正文不足。
  let short = to_bytes("Content-Length: 100\r\n\r\n{}")
  match decode_framed(short) {
    Err(e) => @test.assert_eq(e.code, parse_error_code)
    Ok(_) => fail("正文不足应失败")
  }

  // 错误码即标准值，进程未被终止（可继续后续处理）。
  @test.assert_eq(parse_error_code, -32700)
}
```

---

## 示例 4 · 批量请求：解码 → 逐条分发 → 编码

JSON-RPC 2.0 §6 允许顶层为数组的批量请求。`decode_batch` 按出现顺序逐元素解码；
`dispatch_batch` 逐条复用冻结的单条 `dispatch`，按序汇集各请求响应、**略去通知**；
`encode_batch` 将响应数组编码回字节（**R2.4 / R2.10 / Property 3**）。

```mbt check
///|
test "README · 批量解码分发编码（顺序保持/通知略去）" {
  // 注册一个 ping 处理器，回显 id。
  let router = Router::new()
  router.register("ping", fn(msg) {
    match msg {
      Request(id~, ..) =>
        Some(
          JsonRpcMessage::Response(
            id~,
            result=Some(Json::JStr("pong")),
            error=None,
          ),
        )
      _ => None
    }
  })

  // 批量：请求 ping(1) + 请求 unknown(2) + 通知 note。
  let batch_bytes = to_bytes(
    "[" +
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{}}," +
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"unknown\",\"params\":{}}," +
    "{\"jsonrpc\":\"2.0\",\"method\":\"note\",\"params\":{}}" +
    "]",
  )

  // 解码：三个元素均合法，逐元素 Ok。
  let decoded = match decode_batch(batch_bytes) {
    Ok(rs) => rs
    Err(e) => fail("批量解码应成功：" + e.message)
  }
  @test.assert_eq(decoded.length(), 3)
  let msgs : Array[JsonRpcMessage] = []
  for r in decoded {
    match r {
      Ok(m) => msgs.push(m)
      Err(e) => fail("元素不应失败：" + e.message)
    }
  }

  // 逐条分发：ping → pong 响应；unknown → method-not-found 响应；通知略去。
  let responses = dispatch_batch(msgs, router)
  @test.assert_eq(responses.length(), 2)
  // 第一条响应对应 ping(1)。
  match responses[0] {
    Response(id~, result~, ..) => {
      @test.assert_eq(id, Id::IdNum(1))
      @test.assert_eq(result, Some(Json::JStr("pong")))
    }
    _ => fail("期望 ping 的响应")
  }
  // 第二条响应对应 unknown(2)，携带 method_not_found_code。
  match responses[1] {
    Response(id~, error~, ..) => {
      @test.assert_eq(id, Id::IdNum(2))
      match error {
        Some(e) => @test.assert_eq(e.code, method_not_found_code)
        None => fail("期望 error 对象")
      }
    }
    _ => fail("期望 unknown 的错误响应")
  }

  // 编码响应数组：顶层为 JSON 数组。
  let out = from_bytes(encode_batch(responses))
  @test.assert_eq(out.get_char(0), Some('['))
  @test.assert_eq(out.get_char(out.length() - 1), Some(']'))
}
```

---

## 示例 5 · 批量单元素失败隔离

批量中某一元素非法（如缺 `jsonrpc` 字段）只就地标记为该元素的 `Err`，**不影响**
其余元素的解码（**R2.4 稳健性**）。

```mbt check
///|
test "README · 批量单元素失败被隔离" {
  // 第二个元素缺 jsonrpc 字段 → 非法请求。
  let batch_bytes = to_bytes(
    "[" +
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{}}," +
    "{\"id\":2,\"method\":\"x\"}" +
    "]",
  )
  let decoded = match decode_batch(batch_bytes) {
    Ok(rs) => rs
    Err(e) => fail("批量顶层应解码成功：" + e.message)
  }
  @test.assert_eq(decoded.length(), 2)
  // 第一个元素合法。
  match decoded[0] {
    Ok(Request(method_name~, ..)) => @test.assert_eq(method_name, "ping")
    _ => fail("第一个元素应为合法请求")
  }
  // 第二个元素被隔离为 invalid_request_code 错误，未影响第一个。
  match decoded[1] {
    Err(e) => @test.assert_eq(e.code, invalid_request_code)
    Ok(_) => fail("第二个元素应失败")
  }
}
```

---

## 示例 6 · 请求取消（CancelRegistry / cancel_id_of / cancelled_response）

LSP 客户端经 `$/cancelRequest` 通知携带待取消请求 `id`。`cancel_id_of` 从其
`params` 取出该 id；`CancelRegistry` 以纯数据模型标记取消；`cancelled_response`
为被取消的进行中请求合成携带 `request_cancelled_code` 且 id 一致的错误响应
（**R2.5 / Property 13**）。

```mbt check
///|
test "README · 取消标记与取消响应" {
  // 取消码为新增公开常量，独立于五个标准错误码。
  @test.assert_eq(request_cancelled_code, -32800)

  // $/cancelRequest 通知的 params：{"id": 2}。
  let params = Json::JObj([("id", Json::JNum("2"))])
  let target = match cancel_id_of(params) {
    Some(id) => id
    None => fail("应能取出待取消 id")
  }
  @test.assert_eq(target, Id::IdNum(2))

  // 在登记表中标记取消（纯函数式：返回新实例）。
  let reg = CancelRegistry::new().cancel(target)
  assert_true(reg.is_cancelled(Id::IdNum(2)))
  // 未被取消的 id 不受影响。
  assert_true(!reg.is_cancelled(Id::IdNum(3)))

  // 为被取消的请求合成取消错误响应：携带 request_cancelled_code 且 id 一致。
  match cancelled_response(target) {
    Response(id~, error~, ..) => {
      @test.assert_eq(id, Id::IdNum(2))
      match error {
        Some(e) => @test.assert_eq(e.code, request_cancelled_code)
        None => fail("期望 error 对象")
      }
    }
    _ => fail("期望一条 Response")
  }
}
```

---

## 示例 7 · 请求—响应 id 关联（id_of / correlate）

JSON-RPC 2.0 §5 要求响应 `id` 必与触发它的请求 `id` 相等。`id_of` 取出请求/响应的
`id`（通知无 id → `None`）；`correlate` 校验响应是否关联到某请求（**R2.6 / R2.7**）。

```mbt check
///|
test "README · id 关联校验" {
  let request = JsonRpcMessage::Request(
    id=Id::IdNum(7),
    method_name="hover",
    params=Json::JNull,
  )
  let response = JsonRpcMessage::Response(
    id=Id::IdNum(7),
    result=Some(Json::JNull),
    error=None,
  )
  let mismatch = JsonRpcMessage::Response(
    id=Id::IdNum(8),
    result=Some(Json::JNull),
    error=None,
  )
  let notification = JsonRpcMessage::Notification(
    method_name="note",
    params=Json::JNull,
  )

  // id_of：请求/响应携带 id；通知无 id。
  @test.assert_eq(id_of(request), Some(Id::IdNum(7)))
  @test.assert_eq(id_of(response), Some(Id::IdNum(7)))
  @test.assert_eq(id_of(notification), None)

  // correlate：id 相等才关联。
  assert_true(correlate(request, response))
  assert_true(!correlate(request, mismatch))
  // 通知无 id，永不关联。
  assert_true(!correlate(request, notification))
}
```

---

## 验证方式

```bash
# native 后端校验可执行文档前先导出库路径（R11.5）
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/lsp_binding/README.mbt.md

# 三后端一致性（R11.1）：同一文档套件在三后端均须通过
moon test src/lsp_binding/README.mbt.md --target wasm-gc
moon test src/lsp_binding/README.mbt.md --target js
moon test src/lsp_binding/README.mbt.md --target native
```

预期看到：

```
Total tests: 7, passed: 7, failed: 0.
```

（示例 1~7 的 7 段可执行测试全部通过。）一旦修改实现使其输出与本文档的
`assert_*` 断言不符，`moon test` 会立即报错并提示同步更新文档——这正是 MoonBit
独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
