# lsp_server · 可执行文档

> **方向五（R5）LSP_Server / LSP_Binding** — 完整 LSP 生命周期 · 能力协商 ·
> 增量文档同步 · 位置编码换算 · 扩展语言能力 · push + pull 诊断 · 端到端会话 ·
> 三后端一致。
>
> 本文件既是 `lsp_server` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/lsp_server/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R8.1 / R8.2 / R8.5（可执行文档门禁）**、tasks.md **任务 18.4**。

本文件作为 `lsp_server` 包的黑盒测试运行：

- 可直接调用本包公开 API（`on_initialize` / `on_did_change` / `analyze` /
  `LspSession` / `step` / `negotiate` / `apply_changes` / `position_to_offset` /
  `document_symbols` / `references` / `rename` / `formatting` / `code_actions` /
  `signature_help` / `semantic_tokens` / `folding_ranges` / `pull_diagnostics` /
  `diagnostic_to_json` / `run_session_demo` 等）而无需限定包名；
- 经 `@lsp_binding` 限定访问协议层 API（`decode_message` / `encode_message` /
  `dispatch`、`Router`、`JsonRpcMessage`、`Json`、`Id`、错误码常量等）。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明一个独立条目。
>
> **关于保留字 `method_name`**：`JsonRpcMessage` 的 `method_name~` 为带标签字段，构造与
> 解构时统一使用标签形式（`method_name=...` / `method_name~`），避免与保留字冲突。
>
> **关于黑盒枚举构造**：跨包枚举须用限定形式（`@lsp_binding.JStr(...)`、
> `@lsp_binding.Request(...)`、`@lsp_binding.IdNum(...)` 等）；本包公开枚举
> （`LifecycleState` / `LifecycleEvent` / `PositionEncoding` / `DiagnosticSeverity`
> 等）的构造子在本包黑盒测试内直接可用。
>
> **关于字面 `${`**：内置 DSL 含 `${key}` 引用，但源码中**绝不出现字面 `${`
> 片段**（JS 后端会把悬空 `${` 当作模板字符串插值起始，导致生成代码语法错误）；
> 本文档统一以运行期由字符码拼接的 `dollar_ref` 辅助构造 `${name}`。

---

## paper-to-code 追溯（R8.1 / R8.2）

- **LSP Lifecycle Messages**（`initialize` / `initialized` / `shutdown` /
  `exit`）：会话生命周期为**纯状态机** —— `Uninitialized → Initializing →
  Initialized → ShuttingDown → Exited`，由 `LifecycleState` / `LifecycleEvent` /
  `step` / `LspSession` 承载。`exit` 退出码遵循规范：已收到 `shutdown` 为 `0`，
  否则为 `1`。
- **LSP 能力协商（Client/Server Capabilities）**：服务端仅声明客户端所声明能力的
  子集——由 `ServerCapabilitiesExt` / `InitializeParamsExt` / `negotiate` 承载。
- **LSP PositionEncodingKind**：位置 `character` 列号的单位由位置编码决定，
  默认 `UTF-16`，可协商为 `UTF-8` / `UTF-32`；单个码位在各编码下占用的码元数
  （UTF-16：BMP=1 / 非 BMP=2；UTF-8：1..4；UTF-32：1）——由 `PositionEncoding` /
  `code_units` / `position_to_offset` / `offset_to_position` / `convert_position` /
  `negotiate_encoding` 承载。
  <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#positionEncodingKind>
- **LSP `textDocument/didChange` 与 `TextDocumentSyncKind`**：`Full`（发送全文）
  与 `Incremental`（发送变更区间，按出现顺序逐条作用）——由 `TextDocumentSyncKind` /
  `ContentChange` / `VersionedDocument` / `apply_changes` 承载。
- **LSP Language Features**：`documentSymbol` / `workspace/symbol` /
  `references` / `documentHighlight` / `rename`（`WorkspaceEdit` / `TextEdit`）/
  `formatting` / `codeAction` / `signatureHelp` / `semanticTokens`（5-tuple 增量
  编码）/ `foldingRange`——分别由 `document_symbols` / `workspace_symbols` /
  `references` / `document_highlights` / `rename` / `formatting` / `code_actions` /
  `signature_help` / `semantic_tokens` / `folding_ranges` 承载。
- **LSP 诊断模型 push + pull**：push（`textDocument/publishDiagnostics` 通知）与
  pull（`textDocument/diagnostic` 请求）走同一 `analyze` 投影，故二者诊断等价——
  由 `publish_diagnostics_notification`（push）/ `pull_diagnostics`（pull）/
  `diagnostic_to_json` 承载（`DiagnosticSeverity` 码：Error=1 / Warning=2 /
  Information=3 / Hint=4）。

---

## 开源对标（R8.4）：能力协商 / 文档同步 / 诊断模型

| 维度 | 本库（lsp_server） | rust-analyzer | gopls | tower-lsp | vscode-languageserver-node |
|---|---|---|---|---|---|
| 能力协商 | 纯函数 `negotiate`：服务端能力 ∩ 客户端声明 | `ServerCapabilities` 按客户端能力构建 | 同上，按 client capabilities 裁剪 | 框架透传，由 `LanguageServer` 实现声明 | `ServerCapabilities` 对象声明 |
| 文档同步 | `apply_changes`：Full / Incremental 纯函数应用，越界即 `Err` 不部分应用 | 增量同步 + rope 文本结构 | 增量同步 + 内部缓冲 | `TextDocumentSyncKind` + 框架管理 | `TextDocuments` 内置增量管理器 |
| 位置编码 | `PositionEncoding` 三编码协商 + 往返可逆换算 | UTF-8 优先（可协商 UTF-16） | UTF-16/UTF-8 协商 | 由实现处理 | UTF-16 默认 |
| 诊断模型 | push + pull 同投影、等价 | push + pull（pull 诊断） | push + pull | push + pull | push 为主，框架支持 pull |
| 运行时 | 无：纯函数「文档 → 能力结果」 | tokio / 真实 IO | goroutine / 真实 IO | tokio 异步运行时 | Node 事件循环 |
| 分析范围 | 内置 `key = value` DSL（演示用） | 完整 Rust 语义分析 | 完整 Go 语义分析 | 由实现决定 | 由实现决定 |

## 实现边界（R8.5）

本能力层**刻意停留在「消息与文档模型层」**：

- **消息与文档模型层，无真实 IO 运行时**：生命周期、同步、编码换算与各语言能力
  均以纯函数表达「输入文档 / 事件 → 输出结果」，不实现真实 stdio / socket 收发，
  也不绑定任何异步事件循环；`run_session_demo` 在内存中串联整条会话。
- **分析针对内置 DSL**：扩展语言能力一律建立在既有 `analyze`（极简 `key = value`
  配置 DSL 静态分析）投影之上，**不重写解析**；这是用于演示协议与能力建模的
  最小语言，而非通用语言分析器。
- **单工作区内存多文档**：`workspace_symbols` 在内存 `Array[Analysis]` 上做查询，
  不扫描真实文件系统、不支持多工作区根。
- **既有契约冻结**：`on_initialize` / `on_did_change` / `on_completion` /
  `on_definition` / `on_hover` / `capabilities_to_json` /
  `publish_diagnostics_notification` / `position_from_json` 等既有 API 行为不变；
  全部扩展能力为旁路新增。

---

## 测试夹具：字节 ⇄ 文本转换、字段读取、引用构造

JSON-RPC 报文以 `Bytes` 在传输层流动。下面的辅助函数在文本与字节之间做逐字节
（ASCII 无损）互转，从 JSON 对象按 key 取字段，并在**运行期**由字符码拼接
`${name}` 引用（规避源码字面 `${`）。

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

///|
/// 运行期构造 `${name}`（由字符码拼接 '$' '{' '}'，避免源码字面 `${`）。
fn dollar_ref(name : String) -> String {
  Int::unsafe_to_char(0x24).to_string() +
  Int::unsafe_to_char(0x7B).to_string() +
  name +
  Int::unsafe_to_char(0x7D).to_string()
}
```

---

## 示例 1 · 解码请求 → 分发 → 编码响应（initialize）

端到端展示 LSP 服务端处理一条 `initialize` 请求的主链路（**R5.1 / R5.2 / R5.4**）：

1. 用 `@lsp_binding.decode_message` 把字节报文解码为 `JsonRpcMessage::Request`；
2. 在 `@lsp_binding.Router` 上注册 `initialize` 能力处理器（内部调用本包
   `on_initialize` 并经 `capabilities_to_json` 序列化能力声明），用
   `@lsp_binding.dispatch` 按 `method_name` 分发得到响应；
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
    @lsp_binding.Request(method_name~, ..) =>
      @test.assert_eq(method_name, "initialize")
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
    @lsp_binding.Notification(method_name~, params~) => {
      @test.assert_eq(method_name, "textDocument/didChange")
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
  @test.assert_eq(diags.length(), 1)
  assert_true(diags[0].severity == Error)
  @test.assert_eq(
    diags[0].message,
    "缺少 '='：期望形如 key = value 的赋值",
  )

  // 3) 据诊断构造 publishDiagnostics 通知（服务端主动下发）。
  let publish = publish_diagnostics_notification(uri, diags)
  match publish {
    @lsp_binding.Notification(method_name~, params~) => {
      @test.assert_eq(method_name, "textDocument/publishDiagnostics")
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
    Err(e) => @test.assert_eq(e.code, @lsp_binding.parse_error_code)
    Ok(_) => fail("期望解析错误")
  }
  // 合法 JSON 但缺 jsonrpc 字段 → 非法请求 -32600。
  match @lsp_binding.decode_message(to_bytes("{\"id\":1,\"method\":\"x\"}")) {
    Err(e) => @test.assert_eq(e.code, @lsp_binding.invalid_request_code)
    Ok(_) => fail("期望非法请求错误")
  }
  // 错误码即标准值，进程未被终止（可继续后续处理）。
  @test.assert_eq(@lsp_binding.parse_error_code, -32700)
  @test.assert_eq(@lsp_binding.invalid_request_code, -32600)
}
```

---

## 示例 4 · 分发未知方法 → 合成规范错误响应 → 编码

`dispatch` 对**请求**中未登记的 `method_name` 会合成一条规范的「方法未找到」错误
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
        Some(e) => @test.assert_eq(e.code, @lsp_binding.method_not_found_code)
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

## 示例 5 · 完整生命周期会话（initialize → initialized → shutdown → exit）

LSP 会话生命周期是一台**纯状态机**：`LspSession` 封装当前状态，`handle` 按消息
驱动转移并合成应答；`step` 是底层纯转移函数（**R1.1–R1.6 / R1.8**）。`exit` 退出
码遵循规范——已收到 `shutdown` 为 `0`，否则为 `1`。

```mbt check
///|
test "README · 生命周期会话状态机" {
  let s0 = LspSession::new()
  assert_true(s0.state() == Uninitialized)

  // 1) initialize 请求 → Initializing，回携带 capabilities 的成功响应。
  let init = @lsp_binding.Request(
    id=@lsp_binding.IdNum(1),
    method_name="initialize",
    params=@lsp_binding.JObj([
      (
        "capabilities",
        @lsp_binding.JArr([
          @lsp_binding.JStr("references"),
          @lsp_binding.JStr("rename"),
        ]),
      ),
      ("positionEncodings", @lsp_binding.JArr([@lsp_binding.JStr("utf-16")])),
    ]),
  )
  let (s1, reply1) = s0.handle(init)
  assert_true(s1.state() == Initializing)
  match reply1 {
    Some(@lsp_binding.Response(id~, error~, ..)) => {
      @test.assert_eq(id, @lsp_binding.IdNum(1))
      assert_true(error == None)
    }
    _ => fail("期望 initialize 成功响应")
  }

  // 2) initialized 通知 → Initialized（通知无应答）。
  let (s2, reply2) = s1.handle(
    @lsp_binding.Notification(
      method_name="initialized",
      params=@lsp_binding.JNull,
    ),
  )
  assert_true(s2.state() == Initialized)
  assert_true(reply2 == None)

  // 3) shutdown 请求 → ShuttingDown，回 result=null。
  let (s3, reply3) = s2.handle(
    @lsp_binding.Request(
      id=@lsp_binding.IdNum(2),
      method_name="shutdown",
      params=@lsp_binding.JNull,
    ),
  )
  assert_true(s3.state() == ShuttingDown)
  match reply3 {
    Some(@lsp_binding.Response(result~, ..)) =>
      assert_true(result == Some(@lsp_binding.JNull))
    _ => fail("期望 shutdown 响应 result=null")
  }

  // 4) exit（经纯状态转移 step；已 shutdown → 退出码 0）。
  let exit = step(s3.state(), true, EvExit, @lsp_binding.IdNull)
  assert_true(exit.state == Exited)
  @test.assert_eq(exit.exit_code, Some(0))

  // 健全性：未初始化时收到非 initialize 请求 → invalid_request_code，状态不变。
  let bad = step(
    Uninitialized,
    false,
    EvRequest(method_name="textDocument/hover"),
    @lsp_binding.IdNum(9),
  )
  assert_true(bad.state == Uninitialized)
  match bad.reply {
    Some(@lsp_binding.Response(error~, ..)) =>
      match error {
        Some(e) => @test.assert_eq(e.code, @lsp_binding.invalid_request_code)
        None => fail("期望 error 对象")
      }
    _ => fail("期望一条错误响应")
  }
}
```

---

## 示例 6 · 能力协商：服务端能力 ∩ 客户端声明（negotiate）

`negotiate` 仅声明客户端所声明能力的子集，对客户端未声明的能力一律不予声明
（**R1.7 / R5.1–R5.7**）。

```mbt check
///|
test "README · 能力协商取客户端声明子集" {
  // 客户端声明 references / rename / documentSymbol 三项。
  let client = InitializeParamsExt::new(
    ["references", "rename", "documentSymbol"],
    ["utf-16"],
  )
  let caps = negotiate(client)

  // 声明的能力恰为客户端所声明者。
  assert_true(caps.references_provider)
  assert_true(caps.rename_provider)
  assert_true(caps.document_symbol_provider)
  // 未声明的能力不予声明。
  assert_true(!caps.hover_provider)
  assert_true(!caps.formatting_provider)
  assert_true(!caps.semantic_tokens_provider)

  // 空声明 → 不声明任何能力。
  let none_caps = negotiate(InitializeParamsExt::empty())
  assert_true(none_caps == ServerCapabilitiesExt::none())
}
```

---

## 示例 7 · 位置编码协商与 Position↔offset 换算

位置 `character` 列号的单位由位置编码决定。`negotiate_encoding` 取客户端首选、
无声明回退 `UTF-16`；`code_units` 给出单码位在各编码下的码元数；
`position_to_offset` / `offset_to_position` 在线性 offset 与 `Position` 间往返；
`convert_position` 在两种编码间换算同一字符边界（**R4.1–R4.5**）。

```mbt check
///|
test "README · 位置编码协商与坐标换算" {
  // 协商：无声明回退 UTF-16；有声明取首选。
  assert_true(negotiate_encoding([]) == Utf16)
  assert_true(negotiate_encoding([Utf8, Utf32]) == Utf8)

  // 文本 "a😀b"（emoji 由码位 0x1F600 运行期构造，避免源码字面）。
  let text = "a" + Int::unsafe_to_char(0x1F600).to_string() + "b"

  // 单码位码元数：BMP 外字符在 UTF-16 计 2、UTF-8 计 4、UTF-32 计 1。
  @test.assert_eq(code_units(0x1F600, Utf16), 2)
  @test.assert_eq(code_units(0x1F600, Utf8), 4)
  @test.assert_eq(code_units(0x1F600, Utf32), 1)

  // 'b' 在 UTF-16 下的列号为 3（a=1 + emoji=2）。
  let pos_b : Position = { line: 0, character: 3 }
  let off = match position_to_offset(text, pos_b, Utf16) {
    Some(o) => o
    None => fail("应能换算 offset")
  }
  @test.assert_eq(off, 3)

  // Position↔offset 往返（Property 6）。
  match offset_to_position(text, off, Utf16) {
    Some(p) => assert_true(p == pos_b)
    None => fail("应能逆换算 Position")
  }

  // 跨编码换算往返（Property 7）：UTF-16 → UTF-8 → UTF-16。
  let in_utf8 = match convert_position(text, pos_b, from=Utf16, to=Utf8) {
    Some(p) => p
    None => fail("应能换算到 UTF-8")
  }
  @test.assert_eq(in_utf8.character, 5) // a=1 + emoji=4
  match convert_position(text, in_utf8, from=Utf8, to=Utf16) {
    Some(p) => assert_true(p == pos_b)
    None => fail("应能换算回 UTF-16")
  }
}
```

---

## 示例 8 · 增量文档同步（apply_changes / VersionedDocument）

`apply_changes` 实现 `TextDocumentSyncKind`：`range = None` 为全量替换；
`range = Some(..)` 为增量替换，多条变更按出现顺序逐条作用。越界范围返回
`invalid_params_code` 且**不返回部分应用结果**（**R3.1–R3.5**）。

```mbt check
///|
test "README · 增量与全量文档同步" {
  let uri = "file:///conf.ini"
  let text = "host = localhost\nport = 8080"

  // 1) 增量：把 line 1 的 "8080"（列 [7,11)）替换为 "9090"。
  let r : Range = {
    start: { line: 1, character: 7 },
    end: { line: 1, character: 11 },
  }
  let inc : ContentChange = { range: Some(r), text: "9090" }
  let after_inc = match apply_changes(text, [inc], Utf16) {
    Ok(t) => t
    Err(e) => fail("增量变更应成功：" + e.message)
  }
  @test.assert_eq(after_inc, "host = localhost\nport = 9090")

  // 2) 全量：range = None，整体替换为变更后全文。
  let full : ContentChange = {
    range: None,
    text: "host = localhost\nport = 9090",
  }
  let after_full = match apply_changes(text, [full], Utf16) {
    Ok(t) => t
    Err(e) => fail("全量变更应成功：" + e.message)
  }
  // 增量结果与全量替换结果逐字符相等（Property 5）。
  @test.assert_eq(after_inc, after_full)

  // 3) 带版本文档：成功则文本更新且版本号更新为通知携带版本。
  let doc_v1 : VersionedDocument = { uri, text, version: 1 }
  let doc_v2 = match doc_v1.apply([inc], 2, Utf16) {
    Ok(d) => d
    Err(e) => fail("带版本变更应成功：" + e.message)
  }
  @test.assert_eq(doc_v2.version, 2)
  @test.assert_eq(doc_v2.text, "host = localhost\nport = 9090")

  // 4) 越界范围 → invalid_params_code，且不返回部分应用结果。
  let oob_range : Range = {
    start: { line: 9, character: 0 },
    end: { line: 9, character: 1 },
  }
  let oob : ContentChange = { range: Some(oob_range), text: "x" }
  match apply_changes(text, [oob], Utf16) {
    Err(e) => @test.assert_eq(e.code, @lsp_binding.invalid_params_code)
    Ok(_) => fail("越界变更应失败")
  }
}
```

---

## 示例 9 · documentSymbol / references / workspace_symbol / documentHighlight

这些能力建立在既有 `analyze` 投影之上，输出顺序由源文本出现顺序决定
（**R5.1 / R5.2 / R5.3 / R5.7 / R5.8**）。下例文档：第 0 行定义 `host`，
第 1 行 `url` 引用 `${host}`。

```mbt check
///|
test "README · 符号、引用、工作区符号与高亮" {
  let uri = "file:///app.conf"
  // "host = localhost\nurl = ${host}"（${host} 运行期构造）。
  let text = "host = localhost\n" + "url = " + dollar_ref("host")
  let a = analyze({ uri, text })

  // documentSymbol：当前文档全部键定义（host、url），按出现顺序。
  let syms = document_symbols(a)
  @test.assert_eq(syms.length(), 2)
  @test.assert_eq(syms[0].name, "host")
  @test.assert_eq(syms[1].name, "url")

  // references：host 的定义 + 全部引用（定义在前）。
  let refs = references(a, "host")
  @test.assert_eq(refs.length(), 2)
  // 第一处为定义（line 0，键 token [0,4)）。
  assert_true(
    refs[0] ==
    Location::{
      uri,
      range: {
        start: { line: 0, character: 0 },
        end: { line: 0, character: 4 },
      },
    },
  )
  // 第二处为 line 1 上的 ${host} 引用（[6,13)）。
  @test.assert_eq(refs[1].range.start.line, 1)

  // workspace/symbol：跨内存多文档按子串匹配；"ho" 命中 host，不命中 url。
  let ws = workspace_symbols([a], "ho")
  @test.assert_eq(ws.length(), 1)
  @test.assert_eq(ws[0].uri, uri)

  // documentHighlight：光标落在 host 定义上 → host 的全部出现（定义 + 引用）。
  let hl = document_highlights(a, { line: 0, character: 1 })
  @test.assert_eq(hl.length(), 2)
}
```

---

## 示例 10 · 重命名（rename / WorkspaceEdit / apply_workspace_edit）

`rename` 将某符号的全部出现一致改名，产出 `WorkspaceEdit`：定义处替换裸键、
引用处替换 `${name}` 整体为 `${new_name}`。`apply_workspace_edit` 应用编辑后，
原名全部出现变为新名、其余文本不变（**R5.4**）。

```mbt check
///|
test "README · 重命名产出并应用 WorkspaceEdit" {
  let uri = "file:///app.conf"
  let text = "host = localhost\n" + "url = " + dollar_ref("host")
  let a = analyze({ uri, text })

  // 将 host 重命名为 HOST。
  let edit = rename(a, "host", "HOST")
  @test.assert_eq(edit.changes.length(), 1)
  let (edit_uri, edits) = edit.changes[0]
  @test.assert_eq(edit_uri, uri)
  // 两处编辑：定义（裸 HOST）+ 引用（${HOST}）。
  @test.assert_eq(edits.length(), 2)
  @test.assert_eq(edits[0].new_text, "HOST")
  @test.assert_eq(edits[1].new_text, dollar_ref("HOST"))

  // 应用编辑：原名全部出现变为新名，其余文本不变。
  let renamed = apply_workspace_edit(text, edits)
  let expected = "HOST = localhost\n" + "url = " + dollar_ref("HOST")
  @test.assert_eq(renamed, expected)

  // 重分析后新名出现数 = 原名原出现数（定义 1 + 引用 1）。
  let a2 = analyze({ uri, text: renamed })
  @test.assert_eq(references(a2, "HOST").length(), 2)
  @test.assert_eq(references(a2, "host").length(), 0)
}
```

---

## 示例 11 · 格式化与代码动作（formatting / code_actions）

`formatting` 规范化 `key = value` 等号周边空白，且**幂等**（对规范文本不再产生
编辑）；`code_actions` 针对某条诊断给出快速修复（**R5.5 / R5.6**）。

```mbt check
///|
test "README · 格式化幂等与代码动作" {
  let uri = "file:///fmt.conf"

  // 1) 格式化：把 "host=localhost" 规范为 "host = localhost"。
  let messy = "host=localhost"
  let edits = formatting({ uri, text: messy })
  @test.assert_eq(edits.length(), 1)
  @test.assert_eq(edits[0].new_text, "host = localhost")

  // 2) 幂等：对已规范文本再次格式化不产生任何编辑（Property 17）。
  let normalized = "host = localhost"
  @test.assert_eq(formatting({ uri, text: normalized }).length(), 0)

  // 3) 代码动作：针对「缺少 '='」诊断给出「插入 '='」快速修复。
  let a = analyze({ uri, text: "broken" })
  @test.assert_eq(a.diagnostics.length(), 1)
  let d = a.diagnostics[0]
  assert_true(d.severity == Error)
  let actions = code_actions(a, d)
  @test.assert_eq(actions.length(), 1)
  @test.assert_eq(actions[0].title, "插入 '='")
}
```

---

## 示例 12 · 签名帮助 / 语义着色 / 折叠区间（signatureHelp / semanticTokens / foldingRange）

`signature_help` 给出光标处键的签名；`semantic_tokens` 产出 LSP 5-tuple 增量
编码；`folding_ranges` 把连续内容行块作为折叠范围（**R5.7**）。

```mbt check
///|
test "README · 签名帮助、语义 token 与折叠" {
  let uri = "file:///sem.conf"
  let text = "host = localhost\nport = 8080"
  let a = analyze({ uri, text })

  // signatureHelp：光标落在 host 定义上 → "host = localhost"。
  match signature_help(a, { line: 0, character: 1 }) {
    Some(sig) => @test.assert_eq(sig.label, "host = localhost")
    None => fail("期望签名信息")
  }

  // semanticTokens：两个键定义，5-tuple 增量编码。
  //   host: [deltaLine=0, deltaStart=0, len=4, type=0, mod=0]
  //   port: [deltaLine=1, deltaStart=0, len=4, type=0, mod=0]
  let tokens = semantic_tokens(a)
  @test.assert_eq(tokens, [0, 0, 4, 0, 0, 1, 0, 4, 0, 0])

  // foldingRange：两行连续内容块 → 一个折叠范围 [{0,0}, {1,11}]。
  let folds = folding_ranges({ uri, text })
  @test.assert_eq(folds.length(), 1)
  assert_true(
    folds[0] ==
    Range::{ start: { line: 0, character: 0 }, end: { line: 1, character: 11 } },
  )
}
```

---

## 示例 13 · push + pull 诊断等价（publish_diagnostics / pull_diagnostics）

push 路径（`on_did_change` → `publish_diagnostics_notification`）与 pull 路径
（`pull_diagnostics`）走同一 `analyze` 投影，故二者诊断逐条相等
（**R6.1 / R6.2 / R6.3 / R6.4**）。`diagnostic_to_json` 输出规范严重级别码
（Error=1）。

```mbt check
///|
test "README · push 与 pull 诊断等价、严重码编码" {
  let uri = "file:///diag.conf"
  let text = "broken" // 缺 '=' → 一条 Error 诊断。
  let doc : TextDocument = { uri, text }

  // pull：textDocument/diagnostic 请求 → 当前诊断。
  let pulled = pull_diagnostics(doc)
  @test.assert_eq(pulled.length(), 1)
  assert_true(pulled[0].severity == Error)

  // push：on_did_change 与 pull_diagnostics 走同一投影 → 诊断集合相等。
  let pushed = on_did_change(doc)
  assert_true(pushed == pulled)

  // diagnostic_to_json：严重级别码 Error=1。
  let json = diagnostic_to_json(pulled[0])
  assert_true(jfield(json, "severity") == Some(@lsp_binding.JNum("1")))
  assert_true(jfield(json, "message") != None)
  assert_true(jfield(json, "range") != None)

  // push 通知携带 uri 与 diagnostics 数组。
  match publish_diagnostics_notification(uri, pushed) {
    @lsp_binding.Notification(method_name~, params~) => {
      @test.assert_eq(method_name, "textDocument/publishDiagnostics")
      assert_true(jfield(params, "uri") == Some(@lsp_binding.JStr(uri)))
      assert_true(jfield(params, "diagnostics") != None)
    }
    _ => fail("期望 publishDiagnostics 通知")
  }
}
```

---

## 示例 14 · 端到端会话 demo（run_session_demo）

`run_session_demo` 驱动一份内置 DSL 文档走过完整 LSP 会话：`initialize` →
`initialized` → `didOpen` → 增量 `didChange` → `diagnostics` / `completion` /
`definition` / `references` / `rename` / `hover` → `shutdown` / `exit`。脚本内部
断言「增量 `didChange` 后的诊断 == 对变更后全文做全量替换后的诊断」，并保证
确定性（**R9.1 / R9.2 / R9.3 / R9.4**）。

```mbt check
///|
test "README · 端到端会话 demo 串联全流程" {
  let steps = run_session_demo()

  // 步骤标签序列确定。
  let labels : Array[String] = []
  for s in steps {
    labels.push(s.label)
  }
  @test.assert_eq(labels, [
    "initialize", "initialized", "didOpen", "didChange", "diagnostics", "completion",
    "definition", "references", "rename", "hover", "shutdown", "exit",
  ])

  // 确定性：再次运行得到逐字段相等的步骤序列（Property 10）。
  assert_true(run_session_demo() == steps)

  // didChange 步骤内断言增量 == 全量（文本与诊断），由 demo 暴露为布尔字段。
  let did_change = steps[3].output
  assert_true(
    jfield(did_change, "incrementalEqualsFullText") ==
    Some(@lsp_binding.JBool(true)),
  )
  assert_true(
    jfield(did_change, "incrementalEqualsFullDiagnostics") ==
    Some(@lsp_binding.JBool(true)),
  )

  // exit 步骤：已 shutdown → 退出码 0，状态 Exited。
  let exit_out = steps[11].output
  assert_true(jfield(exit_out, "exitCode") == Some(@lsp_binding.JNum("0")))
}
```

---

## 验证方式

```bash
# native 后端校验可执行文档前先导出库路径
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
Total tests: 14, passed: 14, failed: 0.
```

（示例 1~14 的 14 段可执行测试全部通过。）一旦修改实现使其输出与本文档的
`inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test` 会立即报错并以
最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
