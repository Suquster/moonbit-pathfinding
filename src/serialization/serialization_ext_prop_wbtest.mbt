// serialization_ext_prop_wbtest.mbt —— 序列化增强属性测试（旗舰深化，任务 7.4）。
//
// Feature: production-hardening, Property 4: 序列化往返一致
//   设计依据：production-hardening/design.md「Property 4: R4 序列化往返一致」
//   覆盖三条往返不变量（每条 ≥100 迭代，wasm-gc / js / native 三后端一致）：
//     1. proto 文件 print→parse 往返：parse_proto_file(print_proto_file(f)) == f；
//     2. Any 包装往返：decode_any(encode_any(a)) == a；
//     3. 流式帧化往返：decode_from(encode_to(m)) == m（encode_typed 语义）。
//
// 采用白盒测试（`_wbtest.mbt`）：本属性需在包内直接构造只读 `pub struct`
//   （`AnyValue` / `ProtoFile` / `ServiceDef` / `RpcDef` / `ImportDecl` / `ProtoSchema`
//    等的字段对黑盒只读、不可创建），故置于白盒文件，并经 moon.pkg 的
//   `for "wbtest"` 引入 @infra_pbt 测试期驱动。
//
// 仅新增测试，不修改任何既有签名与既有测试。全程中文注释，禁止循环内字符串 `+`
//   （字符串构建统一走 `Array[Char]` / `Array[String].join`）。

// ─────────────────────────────── 随机原语 ─────────────────────────────────

///|
/// 生成合法标识符：首字符为字母，其后 0~3 个字母数字（长度 1~4）。
/// 保证 print→parse 往返中标识符不被转义、可逐字符还原。
fn sx_ident(rng : @infra_pbt.Rng) -> String {
  let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".to_array()
  let alnum = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".to_array()
  let out : Array[Char] = []
  out.push(letters[rng.next_below(letters.length())])
  let n = rng.next_below(4)
  for _i in 0..<n {
    out.push(alnum[rng.next_below(alnum.length())])
  }
  String::from_array(out)
}

///|
/// 生成点分包名：1~3 个标识符段以 `.` 连接（如 `demo.api`）。pg_expect_ident
/// 可读取点分标识符，故往返保真。
fn sx_dotted(rng : @infra_pbt.Rng) -> String {
  let segs = rng.next_range(1, 3)
  let parts : Array[String] = []
  for _i in 0..<segs {
    parts.push(sx_ident(rng))
  }
  parts.join(".")
}

///|
/// 生成合法 import 路径：1~3 段标识符以 `/` 连接，末尾追加 `.proto`（仅含字母
/// 数字、`/`、`.`，无需字符串转义，print 时直接以 `"..."` 包裹即可往返）。
fn sx_import_path(rng : @infra_pbt.Rng) -> String {
  let segs = rng.next_range(1, 3)
  let parts : Array[String] = []
  for _i in 0..<segs {
    parts.push(sx_ident(rng))
  }
  // 单次顺序拼接（非循环、仅一次 `+`），符合质量门禁对非循环拼接的放行。
  parts.join("/") + ".proto"
}

///|
/// 生成随机 ASCII 字符串（长度 0~10），字符取自字母数字与少量符号（`._-/`）。
/// 用作 `AnyValue.type_url`：经 UTF-8 编解码往返一致。
fn sx_ascii(rng : @infra_pbt.Rng) -> String {
  let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/".to_array()
  let n = rng.next_below(11)
  let out : Array[Char] = []
  for _i in 0..<n {
    out.push(charset[rng.next_below(charset.length())])
  }
  String::from_array(out)
}

///|
/// 生成随机字节数组（长度 0~8，字节值 0~255）。用作 `AnyValue.value` 的不透明
/// 负载。
fn sx_bytes(rng : @infra_pbt.Rng) -> Bytes {
  let n = rng.next_below(9)
  let arr : Array[Byte] = []
  for _i in 0..<n {
    arr.push(rng.next_below(256).to_byte())
  }
  Bytes::from_array(arr)
}

// ───────────────────────── ProtoFile 生成器（保证可往返） ───────────────────

///|
/// 安全标量类型集合：均为 print→parse 逐字符往返的标量（不含消息 / 枚举引用，
/// 故 pg_resolve_enums 为恒等，不会改写字段类型）。
fn sx_scalar_types() -> Array[ProtoType] {
  [
    PInt32,
    PInt64,
    PUInt32,
    PUInt64,
    PSInt32,
    PSInt64,
    PFixed32,
    PFixed64,
    PBool,
    PString,
    PBytes,
    PDouble,
    PFloat,
  ]
}

///|
/// 构造一个「简单消息」：仅含 1~3 个单值标量字段，字段号自 1 连续递增、字段名
/// `f1`..`fk`，无 oneof / map / reserved / 嵌套。此形态由既有 pg_print_message /
/// pg_parse_message 保证往返保真（与 Property 11 的往返生成器同源约束）。
fn sx_simple_message(rng : @infra_pbt.Rng, name : String) -> ProtoMessage {
  let scalars = sx_scalar_types()
  let nfields = rng.next_range(1, 3)
  let fields : Array[ProtoField] = []
  for i in 0..<nfields {
    let num = i + 1
    let t = scalars[rng.next_below(scalars.length())]
    fields.push({
      name: "f" + num.to_string(),
      number: num,
      ptype: t,
      label: LSingular,
      options: [],
    })
  }
  {
    name,
    fields,
    maps: [],
    oneofs: [],
    reserved_numbers: [],
    reserved_names: [],
    nested_messages: [],
    nested_enums: [],
  }
}

///|
/// 构造一条随机 RPC：方法名 / 输入类型 / 输出类型为随机标识符，客户端 / 服务端
/// 流标志随机。输入 / 输出类型按字符串原样存储（解析器不校验是否引用已定义消息），
/// 故任意标识符均可往返。
fn sx_rpc(rng : @infra_pbt.Rng) -> RpcDef {
  {
    name: sx_ident(rng),
    input_type: sx_ident(rng),
    output_type: sx_ident(rng),
    client_stream: rng.next_bool(),
    server_stream: rng.next_bool(),
  }
}

///|
/// 构造一个随机 service：服务名随机，含 0~3 条 RPC（保序）。
fn sx_service(rng : @infra_pbt.Rng) -> ServiceDef {
  let nrpc = rng.next_below(4)
  let rpcs : Array[RpcDef] = []
  for _i in 0..<nrpc {
    rpcs.push(sx_rpc(rng))
  }
  { name: sx_ident(rng), rpcs }
}

///|
/// 随机「合法且 print/parse 可往返」的 `ProtoFile` 生成器（Property 4 / AC4.4）。
///
/// 可往返性保证（关键）：
///   * package_name：半数为空（print 省略 package 行、parse 还原为空串），半数
///     为点分标识符——两种情形均与解析结果一致；
///   * imports：0~3 条，路径仅含字母数字 / `/` / `.`（无需转义），public 标志随机，
///     按登记顺序打印 / 解析，顺序与内容逐条还原；
///   * schema：0~2 个「简单消息」（仅单值标量字段），消息名 `M0`/`M1` 互异、字段
///     号自 1 连续，复用既有 pg_print_message / pg_parse_message 的往返保真；enums
///     固定为空，规避任何枚举回填差异；
///   * services：0~2 个 service，每个含 0~3 条 RPC（含 stream 标志），保序还原。
/// print_proto_file 各类别分段输出、parse_proto_file 按类别分别累积，故各数组顺序
/// 与内容均逐项相等，从而 parse_proto_file(print_proto_file(f)) == f。
fn sx_gen_proto_file() -> @infra_pbt.Gen[ProtoFile] {
  @infra_pbt.Gen::new(fn(rng) {
    // package：随机空 / 点分。
    let package_name = if rng.next_bool() { "" } else { sx_dotted(rng) }
    // imports：0~3 条。
    let imports : Array[ImportDecl] = []
    let nimp = rng.next_below(4)
    for _i in 0..<nimp {
      imports.push({ path: sx_import_path(rng), public: rng.next_bool() })
    }
    // schema：0~2 个简单消息，名互异（M0 / M1）；enums 为空。
    let messages : Array[ProtoMessage] = []
    let nmsg = rng.next_below(3)
    for i in 0..<nmsg {
      messages.push(sx_simple_message(rng, "M" + i.to_string()))
    }
    let schema : ProtoSchema = { messages, enums: [] }
    // services：0~2 个。
    let services : Array[ServiceDef] = []
    let nsvc = rng.next_below(3)
    for _i in 0..<nsvc {
      services.push(sx_service(rng))
    }
    { package_name, imports, schema, services }
  })
}

///|
/// 随机 `AnyValue` 生成器：随机 type_url（ASCII 字符串）+ 随机 value（字节数组）。
fn sx_gen_any() -> @infra_pbt.Gen[AnyValue] {
  @infra_pbt.Gen::new(fn(rng) {
    { type_url: sx_ascii(rng), value: sx_bytes(rng) }
  })
}

// ──────────────────────────────── 属性测试 ────────────────────────────────

///|
/// Feature: production-hardening, Property 4: proto 文件 print→parse 往返
///
/// 对任意随机合法 `ProtoFile` f（随机 package / import / service / rpc / stream
/// 与若干简单 message），打印再解析得到等价模型：
///   parse_proto_file(print_proto_file(f)) == f。
/// 重点验证 package / import / service / rpc / stream 顶层声明的往返保真。
///
/// **Validates: Requirements 4.4**
test "Feature: production-hardening, Property 4: proto 文件 print-parse 往返" {
  let ok = @infra_pbt.holds_for_all(
    sx_gen_proto_file(),
    fn(f) {
      match parse_proto_file(print_proto_file(f)) {
        Ok(f2) => f2 == f
        Err(_) => false
      }
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 4: encode_any/decode_any 往返
///
/// 对任意随机 `AnyValue` a（随机 type_url + 随机 value 字节），有
///   decode_any(encode_any(a)) == a。
///
/// **Validates: Requirements 4.2**
test "Feature: production-hardening, Property 4: encode_any-decode_any 往返" {
  let ok = @infra_pbt.holds_for_all(
    sx_gen_any(),
    fn(a) {
      match decode_any(encode_any(a)) {
        Ok(b) => b == a
        Err(_) => false
      }
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 4: decode_from(encode_to(m)) 往返
///
/// 以 demo schema + demo message，向同一 `ByteSink` 顺序写入 1~5 条消息，再从
/// `ByteSource` 逐条解码：每条解码结果在 encode_typed 语义下与原消息一致
///   （encode_typed(decoded) == encode_typed(original)），且读毕游标耗尽。
/// 随机化「同一流中的消息条数」，验证长度前缀帧的精确定界与顺序读取。
///
/// **Validates: Requirements 4.6**
test "Feature: production-hardening, Property 4: decode_from-encode_to 往返" {
  let schema = parse_proto_full(demo_proto()).unwrap()
  let name = demo_message_name
  let direct = encode_typed(schema, name, demo_message()).unwrap()
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.gen_int_range(1, 5),
    fn(count) {
      let sink = ByteSink::new()
      // 顺序写入 count 条消息（每条为「长度前缀帧 ++ 负载」）。
      let mut i = 0
      while i < count {
        match encode_to(sink, schema, name, demo_message()) {
          Ok(_) => ()
          Err(_) => return false
        }
        i = i + 1
      }
      // 逐条解码并校验 encode_typed 语义下与原消息一致。
      let source = ByteSource::new(sink.to_bytes())
      let mut j = 0
      while j < count {
        match decode_from(source, schema, name) {
          Ok(m) =>
            match encode_typed(schema, name, m) {
              Ok(re) => if re != direct { return false }
              Err(_) => return false
            }
          Err(_) => return false
        }
        j = j + 1
      }
      // 全部消息读毕后游标应正好耗尽。
      source.is_exhausted()
    },
    iters=200,
  )
  assert_true(ok)
}
