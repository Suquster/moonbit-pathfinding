// proto_service.mbt —— proto3 service / rpc / import / package 解析与打印
// （旗舰深化，旁路新增，R4.1 / R4.4 / R4.7）。
//
// 设计依据（production-hardening/design.md §4.1「proto3 service/rpc/import」）：
// 既有 `parse_proto_full`（proto_grammar.mbt，冻结）覆盖 message / enum / 全部
// 标量类型 / oneof / map / 嵌套类型，但**跳过** package / import / service 三类
// 顶层声明。本文件新增「文件级」解析与打印：
//   * `parse_proto_file` —— 在既有终结符与块解析原语之上，额外收集 `package`、
//     `import`（含 `public`）与 `service { rpc ... }`（含 `stream`），message /
//     enum 直接**复用** `pg_parse_message` / `pg_parse_enum` 并经 `pg_resolve_enums`
//     做枚举引用回填，语义与 `parse_proto_full` 完全一致；
//   * `print_proto_file` —— 经结构化代码节点 `CodeNode` + `render_code`
//     （内部 `@infra_text.TextBuilder`，禁止循环内字符串 `+`）物化为 `.proto`
//     源码，与 `parse_proto_file` 构成**对偶**：`parse_proto_file(print_proto_file(f))`
//     还原与 `f` 等价的模型（R4.4 往返，属性测试见任务 7.4）。
//
// 严格旁路扩展：不修改任何既有签名（`parse_proto_full` / `print_proto` /
// `ProtoSchema` / `ParseError` 等保持不变）。
//
// 失败契约（R4.7）：任何非法 proto3 语法返回携带行列位置（line/col/offset）的
// `ParseError`（复用既有 `ParseError::at`），且失败时不构造 `ProtoFile`。
//
// 复用的同包私有原语（均构建于 @parser_combinator 的 Input/Pos 模型）：
//   skip_trivia / parse_ident / try_char / skip_until / skip_block /
//   pg_expect_ident / pg_expect_char / pg_parse_string_lit /
//   pg_parse_message / pg_parse_enum / pg_resolve_enums /
//   pg_print_message / pg_print_enum / pg_is_nested_name。

// ─────────────────────────────── 数据模型 ─────────────────────────────────

///|
/// 单个 RPC 方法定义。
///
///   * `name`          —— 方法名；
///   * `input_type`    —— 请求消息类型名（原样存储，含可能的包前缀）；
///   * `output_type`   —— 响应消息类型名；
///   * `client_stream` —— 入参是否为 `stream`（客户端流）；
///   * `server_stream` —— 返回是否为 `stream`（服务端流）。
pub struct RpcDef {
  name : String
  input_type : String
  output_type : String
  client_stream : Bool
  server_stream : Bool
} derive(Eq, Show)

///|
/// 一个 service 定义：服务名 + 有序 RPC 列表。
pub struct ServiceDef {
  name : String
  rpcs : Array[RpcDef]
} derive(Eq, Show)

///|
/// 一条 `import` 声明：被导入文件路径 + 是否为 `import public`。
pub struct ImportDecl {
  path : String
  public : Bool
} derive(Eq, Show)

///|
/// 一个完整 `.proto` 文件模型（文件级，旁路于既有 `ProtoSchema`）。
///
///   * `package_name` —— `package` 声明的包名（无则为空串）；
///   * `imports`      —— 有序的 `import` 声明；
///   * `schema`       —— 复用既有 `ProtoSchema`（message / enum 部分）；
///   * `services`     —— 有序的 service 定义。
pub struct ProtoFile {
  package_name : String
  imports : Array[ImportDecl]
  schema : ProtoSchema
  services : Array[ServiceDef]
} derive(Eq, Show)

// ─────────────────────────────── 解析（文件级） ────────────────────────────

///|
/// 解析可选的 `stream` 前缀（出现在 rpc 入/出参类型之前）。
///
/// 返回 `(是否为 stream, 推进后的输入)`。当下一个标识符不是 `stream` 时，**不**
/// 消费它（返回 skip_trivia 后的原始位置），交由后续类型解析读取。
fn ps_parse_stream_opt(
  input : @parser_combinator.Input,
) -> (Bool, @parser_combinator.Input) {
  let a = skip_trivia(input)
  match parse_ident(a) {
    Some((name, r)) =>
      if name == "stream" {
        (true, skip_trivia(r))
      } else {
        (false, a)
      }
    None => (false, a)
  }
}

///|
/// 解析一条 `rpc M(Req) returns (Resp);`（输入位于 `rpc` 关键字之后）。
///
/// 支持入/出参的 `stream` 前缀，以及方法体为 `;` 或 `{ ... }`（块体被跳过）。
fn ps_parse_rpc(
  after_kw : @parser_combinator.Input,
  rpcs : Array[RpcDef],
) -> Result[@parser_combinator.Input, ParseError] {
  let a1 = skip_trivia(after_kw)
  let (mname, r1) = match pg_expect_ident(a1, "rpc 后期望方法名") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let r2 = skip_trivia(r1)
  let r3 = match pg_expect_char(r2, '(', "rpc 方法名后期望 '('") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let (client_stream, r4) = ps_parse_stream_opt(r3)
  let (in_ty, r5) = match pg_expect_ident(r4, "rpc 期望输入类型") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let r6 = skip_trivia(r5)
  let r7 = match pg_expect_char(r6, ')', "rpc 输入类型后期望 ')'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let r8 = skip_trivia(r7)
  let (rkw, r9) = match pg_expect_ident(r8, "rpc 期望 'returns'") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  if rkw != "returns" {
    return Err(ParseError::at(r8.pos, "rpc 期望 'returns'"))
  }
  let r10 = skip_trivia(r9)
  let r11 = match pg_expect_char(r10, '(', "'returns' 后期望 '('") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let (server_stream, r12) = ps_parse_stream_opt(r11)
  let (out_ty, r13) = match pg_expect_ident(r12, "rpc 期望输出类型") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let r14 = skip_trivia(r13)
  let r15 = match pg_expect_char(r14, ')', "rpc 输出类型后期望 ')'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let r16 = skip_trivia(r15)
  // 方法体：`;`（无选项）或 `{ ... }`（选项块，整体跳过）。
  let r17 = match r16.peek() {
    Some('{') =>
      match skip_block(r16.advance()) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
    Some(';') => r16.advance()
    _ => return Err(ParseError::at(r16.pos, "rpc 期望 ';' 或 '{'"))
  }
  rpcs.push({
    name: mname,
    input_type: in_ty,
    output_type: out_ty,
    client_stream,
    server_stream,
  })
  Ok(r17)
}

///|
/// 解析一个 `service S { rpc ...; }` 块（输入位于 `service` 关键字之后）。
fn ps_parse_service(
  after_kw : @parser_combinator.Input,
  services : Array[ServiceDef],
) -> Result[@parser_combinator.Input, ParseError] {
  let a1 = skip_trivia(after_kw)
  let (name, after_name) = match
    pg_expect_ident(a1, "service 后期望服务名") {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let bb = skip_trivia(after_name)
  let mut cur = match pg_expect_char(bb, '{', "服务名后期望 '{'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let rpcs : Array[RpcDef] = []
  let mut done = false
  while !done {
    cur = skip_trivia(cur)
    match cur.peek() {
      None => return Err(ParseError::at(cur.pos, "service 块未闭合"))
      Some('}') => {
        cur = cur.advance()
        done = true
      }
      Some(';') => cur = cur.advance()
      _ => {
        let (tok, after_tok) = match
          pg_expect_ident(cur, "service 成员期望标识符") {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        if tok == "rpc" {
          match ps_parse_rpc(after_tok, rpcs) {
            Ok(next) => cur = next
            Err(e) => return Err(e)
          }
        } else if tok == "option" {
          match skip_until(after_tok, ';', "service 选项缺少结尾 ';'") {
            Ok(next) => cur = next
            Err(e) => return Err(e)
          }
        } else {
          return Err(ParseError::at(cur.pos, "service 成员期望 'rpc'"))
        }
      }
    }
  }
  services.push({ name, rpcs })
  Ok(cur)
}

///|
/// 解析一条 `import [public] "path";`（输入位于 `import` 关键字之后）。
fn ps_parse_import(
  after_kw : @parser_combinator.Input,
  imports : Array[ImportDecl],
) -> Result[@parser_combinator.Input, ParseError] {
  let a1 = skip_trivia(after_kw)
  // 可选的 `public` 修饰；其余标识符（如 `weak`）按非 public 处理后再读路径。
  let (is_public, a2) = match parse_ident(a1) {
    Some(("public", r)) => (true, skip_trivia(r))
    Some(("weak", r)) => (false, skip_trivia(r))
    _ => (false, a1)
  }
  let (path, r1) = match pg_parse_string_lit(a2) {
    Some(p) => p
    None => return Err(ParseError::at(a2.pos, "import 期望字符串路径"))
  }
  let r2 = skip_trivia(r1)
  let r3 = match pg_expect_char(r2, ';', "import 期望 ';'") {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  imports.push({ path, public: is_public })
  Ok(r3)
}

///|
/// 解析一份完整的 `.proto` 源码为 `ProtoFile`（R4.1）。
///
/// 顶层声明处理：
///   * `syntax` / `option` —— 跳过至 `;`；
///   * `package x.y;`      —— 收集包名；
///   * `import [public] "p.proto";` —— 收集导入声明（有序）；
///   * `message { ... }` / `enum { ... }` —— 复用 `pg_parse_message` /
///     `pg_parse_enum`（与 `parse_proto_full` 同一实现）；
///   * `service S { rpc ... }` —— 收集服务与 RPC（含 `stream`）。
///
/// 解析末尾经 `pg_resolve_enums` 把引用到已知枚举名的 `PMessage` 回填为 `PEnum`，
/// 与 `parse_proto_full` 行为一致。任何语法错误返回携带行列位置的 `ParseError`
/// （R4.7），失败时不构造 `ProtoFile`。
pub fn parse_proto_file(src : String) -> Result[ProtoFile, ParseError] {
  let messages : Array[ProtoMessage] = []
  let enums : Array[EnumDef] = []
  let imports : Array[ImportDecl] = []
  let services : Array[ServiceDef] = []
  let mut package_name = ""
  let mut input = @parser_combinator.Input::from_string(src)
  while true {
    input = skip_trivia(input)
    if input.is_eof() {
      break
    }
    let (kw, after_kw) = match
      pg_expect_ident(
        input, "期望顶层声明（syntax / package / import / message / enum / service）",
      ) {
      Ok(p) => p
      Err(e) => return Err(e)
    }
    if kw == "message" {
      match pg_parse_message(after_kw, "", messages, enums) {
        Ok((next, _)) => input = next
        Err(e) => return Err(e)
      }
    } else if kw == "enum" {
      match pg_parse_enum(after_kw, "", enums) {
        Ok((next, _)) => input = next
        Err(e) => return Err(e)
      }
    } else if kw == "service" {
      match ps_parse_service(after_kw, services) {
        Ok(next) => input = next
        Err(e) => return Err(e)
      }
    } else if kw == "package" {
      let a1 = skip_trivia(after_kw)
      let (name, r1) = match pg_expect_ident(a1, "package 后期望包名") {
        Ok(p) => p
        Err(e) => return Err(e)
      }
      let r2 = skip_trivia(r1)
      let r3 = match pg_expect_char(r2, ';', "package 声明期望 ';'") {
        Ok(c) => c
        Err(e) => return Err(e)
      }
      package_name = name
      input = r3
    } else if kw == "import" {
      match ps_parse_import(after_kw, imports) {
        Ok(next) => input = next
        Err(e) => return Err(e)
      }
    } else {
      // syntax / option 等：跳到 ';'。
      match skip_until(after_kw, ';', "顶层语句缺少结尾 ';'") {
        Ok(r) => input = r
        Err(e) => return Err(e)
      }
    }
  }
  let schema = pg_resolve_enums({ messages, enums })
  Ok({ package_name, imports, schema, services })
}

// ─────────────────────────────── 打印（文件级，对偶） ───────────────────────

///|
/// 渲染 `package x.y;` 一行的内容（不含尾随换行，交由 `CLine` 追加）。
fn ps_package_line(name : String) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("package ")
  tb.push_str(name)
  tb.push_char(';')
  tb.build()
}

///|
/// 渲染 `import [public] "path";` 一行的内容（不含尾随换行）。
fn ps_import_line(imp : ImportDecl) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("import ")
  if imp.public {
    tb.push_str("public ")
  }
  tb.push_char('"')
  tb.push_str(imp.path)
  tb.push_char('"')
  tb.push_char(';')
  tb.build()
}

///|
/// 渲染单条 `rpc M(Req) returns (Resp);` 一行的内容（不含尾随换行）。
///
/// 经 `@infra_text.TextBuilder` 顺序追加片段，避免多次顺序字符串 `+`。
fn ps_rpc_line(rpc : RpcDef) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("rpc ")
  tb.push_str(rpc.name)
  tb.push_char('(')
  if rpc.client_stream {
    tb.push_str("stream ")
  }
  tb.push_str(rpc.input_type)
  tb.push_str(") returns (")
  if rpc.server_stream {
    tb.push_str("stream ")
  }
  tb.push_str(rpc.output_type)
  tb.push_str(");")
  tb.build()
}

///|
/// 渲染服务头 `service Name {` 的内容（不含尾随换行）。
fn ps_service_header(name : String) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("service ")
  tb.push_str(name)
  tb.push_str(" {")
  tb.build()
}

///|
/// 由一个 service 构造结构化代码块节点（`CBlock`），RPC 各占一行（缩进一级）。
fn ps_service_node(svc : ServiceDef) -> CodeNode {
  let body : Array[CodeNode] = []
  for rpc in svc.rpcs {
    body.push(CLine(ps_rpc_line(rpc)))
  }
  CBlock(header=ps_service_header(svc.name), body~, close="}")
}

///|
/// 将 `ProtoFile` 规范化打印为 `.proto` 源码（R4.4，与 `parse_proto_file` 对偶）。
///
/// 经结构化代码节点 `CodeNode` + `render_code`（内部 `@infra_text.TextBuilder`，
/// 禁止循环内字符串 `+`）物化。输出形态固定且可被 `parse_proto_file` 重新解析为
/// 等价模型：
///
///   1. `syntax = "proto3";`；
///   2. `package ...;`（仅当包名非空）；
///   3. 各 `import [public] "...";`（按登记顺序）；
///   4. 顶层 message / enum（复用既有 `pg_print_message` / `pg_print_enum`，
///      其本身与 `parse_proto_full` 往返一致）；
///   5. 各 service 块（含 `stream` 前缀）。
///
/// message / enum 段已自带规范缩进与换行，故以 `CRaw` 原样并入；其余行经 `CLine`
/// / `CBlock` 由 `render_code` 统一控制换行与缩进。
pub fn print_proto_file(file : ProtoFile) -> String {
  let nodes : Array[CodeNode] = []
  nodes.push(CLine("syntax = \"proto3\";"))
  if file.package_name != "" {
    nodes.push(CLine(ps_package_line(file.package_name)))
  }
  for imp in file.imports {
    nodes.push(CLine(ps_import_line(imp)))
  }
  for m in file.schema.messages {
    if !pg_is_nested_name(m.name) {
      nodes.push(CRaw(pg_print_message(file.schema, m, 0)))
    }
  }
  for e in file.schema.enums {
    if !pg_is_nested_name(e.name) {
      nodes.push(CRaw(pg_print_enum(e, 0)))
    }
  }
  for svc in file.services {
    nodes.push(ps_service_node(svc))
  }
  render_code(CSeq(nodes))
}

// ──────────────────────────────── 内联烟雾测试 ─────────────────────────────
// 完整属性测试（print→parse 往返，≥100 迭代，三后端）见任务 7.4；此处仅做最小
// 冒烟：解析一个含 service / import / package 的样例、并往返一次。

///|
/// 烟雾：解析含 syntax / package / import / message / service 的样例文件。
test "parse_proto_file 解析 service 样例冒烟" {
  let src =
    #|syntax = "proto3";
    #|package demo.api;
    #|import "common.proto";
    #|import public "types.proto";
    #|message Req { int32 id = 1; }
    #|message Resp { string msg = 1; }
    #|service Greeter {
    #|  rpc Unary(Req) returns (Resp);
    #|  rpc ClientStream(stream Req) returns (Resp);
    #|  rpc BidiStream(stream Req) returns (stream Resp);
    #|}
  let file = match parse_proto_file(src) {
    Ok(f) => f
    Err(e) => {
      fail("解析失败：\{e}")
      return
    }
  }
  assert_eq(file.package_name, "demo.api")
  assert_eq(file.imports.length(), 2)
  assert_eq(file.imports[0], { path: "common.proto", public: false })
  assert_eq(file.imports[1], { path: "types.proto", public: true })
  assert_eq(file.schema.messages.length(), 2)
  assert_eq(file.services.length(), 1)
  let svc = file.services[0]
  assert_eq(svc.name, "Greeter")
  assert_eq(svc.rpcs.length(), 3)
  assert_eq(svc.rpcs[0], {
    name: "Unary",
    input_type: "Req",
    output_type: "Resp",
    client_stream: false,
    server_stream: false,
  })
  assert_eq(svc.rpcs[1].client_stream, true)
  assert_eq(svc.rpcs[1].server_stream, false)
  assert_eq(svc.rpcs[2].client_stream, true)
  assert_eq(svc.rpcs[2].server_stream, true)
}

///|
/// 烟雾：print_proto_file → parse_proto_file 往返得到等价模型（R4.4 对偶）。
test "print_proto_file 与 parse_proto_file 往返冒烟" {
  let src =
    #|syntax = "proto3";
    #|package demo.api;
    #|import public "types.proto";
    #|message Req { int32 id = 1; }
    #|message Resp { string msg = 1; }
    #|service Greeter {
    #|  rpc Unary(Req) returns (Resp);
    #|  rpc BidiStream(stream Req) returns (stream Resp);
    #|}
  let file = match parse_proto_file(src) {
    Ok(f) => f
    Err(e) => {
      fail("首次解析失败：\{e}")
      return
    }
  }
  let printed = print_proto_file(file)
  let reparsed = match parse_proto_file(printed) {
    Ok(f) => f
    Err(e) => {
      fail("重解析失败：\{e}\n打印结果：\n\{printed}")
      return
    }
  }
  assert_eq(reparsed, file)
}

///|
/// 烟雾：非法语法（rpc 缺少 returns）返回携带位置的 ParseError（R4.7）。
test "parse_proto_file 非法语法报告位置冒烟" {
  let src =
    #|syntax = "proto3";
    #|service S {
    #|  rpc M(Req) (Resp);
    #|}
  match parse_proto_file(src) {
    Ok(_) => fail("非法语法本应解析失败")
    Err(e) => {
      // 错误应定位到第 3 行（rpc 行），且 message 含 'returns'。
      assert_eq(e.line, 3)
      assert_true(e.message.contains("returns"))
    }
  }
}
