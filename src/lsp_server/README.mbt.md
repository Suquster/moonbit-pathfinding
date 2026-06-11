# lsp_server · 可执行文档

> **方向五（R5）LSP_Server / LSP_Binding** — JSON-RPC 2.0 解码 · 能力分发 · 编码响应 · 三后端一致。
>
> 本文件既是 `lsp_server` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/lsp_server/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）**，tasks.md **任务 14.5**。

本文件作为 `lsp_server` 包的黑盒测试运行：

- 可直接调用本包公开 API（`on_initialize` / `on_did_change` / `analyze` /
  `capabilities_to_json` / `publish_diagnostics_notification` 等）而无需限定包名；
- 经 `@lsp_binding` 限定访问协议层 API（`decode_message` / `encode_message` /
  `dispatch`、`Router`、`JsonRpcMessage`、`Json`、`Id`、错误码常量等）。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明一个独立条目。
>
> **关于保留字 `method`**：`JsonRpcMessage` 的 `method~` 为带标签字段，构造与
> 解构时统一使用标签形式（`method=...` / `method~`），避免与保留字冲突。
>
> **关于黑盒枚举构造**：跨包枚举须用限定形式（`@lsp_binding.JStr(...)`、
> `@lsp_binding.Request(...)`、`@lsp_binding.IdNum(...)` 等）或对应构造函数。

---

## 测试夹具：字节 ⇄ 文本转换

JSON-RPC 报文以 `Bytes` 在传输层流动。下面两个辅助函数在文本与字节之间做
逐字节（ASCII 无损）互转，与 `@lsp_binding` 内部约定一致——JSON-RPC 控制结构
均为 ASCII，故示例中的报文与键值均采用 ASCII。

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
/// 在 JSON 对象中按 key 取字段值；非对象或缺失返回 None。
fn jfield(json : @lsp_binding.Json, key : String) -> @lsp_binding.Json? {
  match json {
    @lsp_binding.JObj(fields) => {
      for kv in fields {
        let (k, v) = kv
        if k == key {
          return Some(v)
        }
      }
      None
    }
    _ => None
  }
}
```

---

## 示例 1 · 解码请求 → 分发 → 编码响应（initialize）

端到端展示 LSP 服务端处理一条 `initialize` 请求的主链路（**R5.1 / R5.2 / R5.4**）：

1. 用 `@lsp_binding.decode_message` 把字节报文解码为 `JsonRpcMessage::Request`；
2. 在 `@lsp_binding.Router` 上注册 `initialize` 能力处理器（内部调用本包
   `on_initialize` 并经 `capabilities_to_json` 序列化能力声明），用
   `@lsp_binding.dispatch` 按 `method` 分发得到响应；
3. 用 `@lsp_binding.encode_message` 把响应编码回字节。

```mbt check
///|
test "README · 解码 initialize 请求并分发、编码响应" {
  // 1) 注册 initialize 能力处理器到路由表。
  let router = @lsp_binding.Router::new()
  router.register("initialize", fn(msg) {
    match msg {
      @lsp_binding.Request(id~, ..) => {
        let caps = on_initialize({ root_uri: None })
        Some(
          @lsp_binding.Response(
            id~,
            result=Some(capabilities_to_json(caps)),
            error=None,
          ),
        )
      }
      _ => None
    }
  })

  // 2) 解码客户端发来的 initialize 请求字节报文。
  let req_bytes = to_bytes(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file:///proj\"}}",
  )
  let msg = match @lsp_binding.decode_message(req_bytes) {
    Ok(m) => m
    Err(e) => fail("解码应成功，却得到错误：" + e.message)
  }
  // 确认解码为 method=initialize 的请求。
  match msg {
    @lsp_binding.Request(method~, ..) => assert_eq(method, "initialize")
    _ => fail("期望解码为 Request")
  }

  // 3) 分发到 initialize 处理器，得到声明四项能力的响应。
  let resp = match @lsp_binding.dispatch(msg, router) {
    Some(r) => r
    None => fail("期望分发产生一条响应")
  }

  // 4) 编码响应回字节，并校验 JSON 文本快照。
  let out = from_bytes(@lsp_binding.encode_message(resp))
  inspect(
    out,
    content="{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"diagnosticProvider\":true,\"completionProvider\":true,\"definitionProvider\":true,\"hoverProvider\":true}}",
  )
}
```

---

## 示例 2 · 解码 didChange 通知 → 重分析 → 发布诊断

`didChange` 是**通知**（无 id，不期待响应）。服务端解码后重分析文档，再主动
发出 `textDocument/publishDiagnostics` 通知（**R5.2 / R5.5**）。下例文档首行缺少
`=`，`on_did_change` 应产出一条 `Error` 诊断，并据此构造 publishDiagnostics 通知。

```mbt check
///|
test "README · 解码 didChange 通知并发布诊断" {
  // 1) 解码 didChange 通知（无 id → Notification）。
  let note_bytes = to_bytes(
    "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///a.conf\",\"text\":\"no eq here\"}}}",
  )
  let msg = match @lsp_binding.decode_message(note_bytes) {
    Ok(m) => m
    Err(e) => fail("解码应成功，却得到错误：" + e.message)
  }
  // 从通知 params 中取出文档 uri 与正文。
  let (uri, text) = match msg {
    @lsp_binding.Notification(method~, params~) => {
      assert_eq(method, "textDocument/didChange")
      let td = match jfield(params, "textDocument") {
        Some(j) => j
        None => fail("缺少 textDocument 字段")
      }
      let uri = match jfield(td, "uri") {
        Some(@lsp_binding.JStr(s)) => s
        _ => fail("缺少 uri 字段")
      }
      let text = match jfield(td, "text") {
        Some(@lsp_binding.JStr(s)) => s
        _ => fail("缺少 text 字段")
      }
      (uri, text)
    }
    _ => fail("期望解码为 Notification")
  }

  // 2) 重分析文档，产出诊断（首行缺 '=' → 一条 Error 诊断）。
  let diags = on_did_change({ uri, text })
  assert_eq(diags.length(), 1)
  assert_true(diags[0].severity == Error)
  assert_eq(diags[0].message, "缺少 '='：期望形如 key = value 的赋值")

  // 3) 据诊断构造 publishDiagnostics 通知（服务端主动下发）。
  let publish = publish_diagnostics_notification(uri, diags)
  match publish {
    @lsp_binding.Notification(method~, params~) => {
      assert_eq(method, "textDocument/publishDiagnostics")
      // params 携带 uri 与 diagnostics 两个字段。
      assert_true(jfield(params, "uri") == Some(@lsp_binding.JStr(uri)))
      assert_true(jfield(params, "diagnostics") != None)
    }
    _ => fail("期望构造出一条 publishDiagnostics 通知")
  }
}
```

---

## 示例 3 · 非法消息返回规范错误（不终止进程）

`decode_message` 对非法输入返回**符合 JSON-RPC 2.0 规范**的结构化错误
（以 `Result::Err` 承载），而非 panic/中止进程（**R5.3**）。下例覆盖两类非法：
无法解析为合法 JSON（`parse_error_code`），与缺失 `jsonrpc` 字段
（`invalid_request_code`）。

```mbt check
///|
test "README · 非法消息返回规范错误码" {
  // 非法 JSON → 解析错误 -32700。
  match @lsp_binding.decode_message(to_bytes("{ not json ")) {
    Err(e) => assert_eq(e.code, @lsp_binding.parse_error_code)
    Ok(_) => fail("期望解析错误")
  }
  // 合法 JSON 但缺 jsonrpc 字段 → 非法请求 -32600。
  match @lsp_binding.decode_message(to_bytes("{\"id\":1,\"method\":\"x\"}")) {
    Err(e) => assert_eq(e.code, @lsp_binding.invalid_request_code)
    Ok(_) => fail("期望非法请求错误")
  }
  // 错误码即标准值，进程未被终止（可继续后续处理）。
  assert_eq(@lsp_binding.parse_error_code, -32700)
  assert_eq(@lsp_binding.invalid_request_code, -32600)
}
```

---

## 示例 4 · 分发未知方法 → 合成规范错误响应 → 编码

`dispatch` 对**请求**中未登记的 `method` 会合成一条规范的「方法未找到」错误
响应（`method_not_found_code` = -32601），交由调用方编码下发（**R5.2 / R5.3**）。

```mbt check
///|
test "README · 未知方法分发合成 method-not-found 错误响应" {
  let router = @lsp_binding.Router::new() // 空路由表：未登记任何方法。
  let req_bytes = to_bytes(
    "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"textDocument/unknown\",\"params\":{}}",
  )
  let msg = match @lsp_binding.decode_message(req_bytes) {
    Ok(m) => m
    Err(e) => fail("解码应成功，却得到错误：" + e.message)
  }
  // 分发：方法未找到 → 合成错误响应。
  let resp = match @lsp_binding.dispatch(msg, router) {
    Some(r) => r
    None => fail("期望合成一条错误响应")
  }
  // 校验错误码并编码下发。
  match resp {
    @lsp_binding.Response(error~, ..) =>
      match error {
        Some(e) => assert_eq(e.code, @lsp_binding.method_not_found_code)
        None => fail("期望响应携带 error 对象")
      }
    _ => fail("期望一条 Response")
  }
  let out = from_bytes(@lsp_binding.encode_message(resp))
  inspect(
    out,
    content="{\"jsonrpc\":\"2.0\",\"id\":99,\"error\":{\"code\":-32601,\"message\":\"Method not found: textDocument/unknown\"}}",
  )
}
```

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/lsp_server/README.mbt.md

# 三后端一致性（R11.1）：同一文档套件在三后端均须通过
moon test src/lsp_server/README.mbt.md --target wasm-gc
moon test src/lsp_server/README.mbt.md --target js
moon test src/lsp_server/README.mbt.md --target native
```

预期看到：

```
Total tests: 4, passed: 4, failed: 0.
```

（示例 1~4 的 4 段可执行测试全部通过。）一旦修改实现使其输出与本文档的
`inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test` 会立即报错并以
最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
