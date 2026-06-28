// streaming.mbt —— `google.protobuf.Any` 编解码与流式（帧化）类型编解码
// （旗舰深化，旁路新增，R4.2 / R4.5 / R4.6）。
//
// 设计依据（production-hardening/design.md §4.3「Any 类型与流式编解码」）：
// 在既有 wire 原语（write_varint / read_varint，wire.mbt，同包私有）与既有
// 模式驱动的类型化编解码（encode_typed / decode_typed，typed.mbt，冻结）之上，
// 旁路新增两组能力：
//
//   1. Any 包装（R4.2）—— `AnyValue { type_url, value }` 以 protobuf 官方
//      `google.protobuf.Any` 的 wire 形态编码：field 1 = type_url（string，
//      wire 类型 Len），field 2 = value（bytes，wire 类型 Len）。`encode_any` /
//      `decode_any` 构成对偶，满足往返一致 `decode_any(encode_any(a)) == a`。
//
//   2. 流式帧化编解码（R4.5 / R4.6）—— `ByteSink`（可累积字节的写入端）与
//      `ByteSource`（带游标的读取端）配合 `encode_to` / `decode_from`，把一条或
//      多条消息以「长度前缀帧」顺序排布到同一字节流：`encode_to` 委派既有
//      `encode_typed` 得到负载，再写入 `varint(长度) ++ 负载`；`decode_from` 从
//      source 当前游标读出长度前缀，截取该长度的负载切片，推进游标后委派既有
//      `decode_typed` 解码。长度前缀使单一流可承载多条消息并精确定界，满足
//      `decode_from(encode_to(m)) == m`，且支持顺序读多条（每读一条游标前移）。
//
// 严格旁路扩展：不修改任何既有签名（encode_typed / decode_typed /
// TypedMessage / DecodeError / base64 / wire 原语等保持不变）。
//
// 失败契约：编码阶段（encode_to）失败原样透传 encode_typed 的 `DecodeError`；
// 解码阶段（decode_any / decode_from）对越界 / 截断 / 畸形 varint 返回携带字节
// 偏移的 `DecodeError`（复用 wire.mbt 的 read_varint 失败语义），绝不返回部分
// 构造的对象。全程无 abort/panic/todo 占位。
//
// 复用的同包私有原语：
//   * write_varint / read_varint（wire.mbt）—— base-128 变长整数读写；
//   * string_to_bytes / bytes_to_string（typed.mbt）—— UTF-8 串字节互转；
//   * encode_typed / decode_typed（typed.mbt）—— 模式驱动类型编解码。

// ─────────────────────────── Any 编码常量 ────────────────────────────────

///|
/// `google.protobuf.Any` 的 `type_url` 字段号（官方定义为 1）。命名以规避
/// magic number。
const ANY_FIELD_TYPE_URL : Int = 1

///|
/// `google.protobuf.Any` 的 `value` 字段号（官方定义为 2）。
const ANY_FIELD_VALUE : Int = 2

///|
/// 由字段号与 `Len`（长度前缀）wire 类型合成 wire tag：`tag = (number<<3) | wire`。
/// 统一走此构造，避免在函数体内散落 `0x0A` / `0x12` 之类的 magic number。
fn any_len_tag(field_number : Int) -> UInt64 {
  (field_number.to_uint64() << 3) | WireType::Len.code().to_uint64()
}

// ─────────────────────────────── AnyValue ────────────────────────────────

///|
/// `google.protobuf.Any` 的模型：
///
///   * `type_url` —— 被包装消息的类型标识（如 `type.googleapis.com/pkg.Msg`）；
///   * `value`    —— 被包装消息的已编码字节（不透明负载）。
pub struct AnyValue {
  type_url : String
  value : Bytes
} derive(Eq, Debug)

///|
/// 将 `AnyValue` 编码为 `google.protobuf.Any` 形态的字节序列。
///
/// 布局（与官方 wire 形态一致）：
///   `tag(field 1, Len) ++ varint(len(type_url_utf8)) ++ type_url_utf8`
/// `++ tag(field 2, Len) ++ varint(len(value)) ++ value`
///
/// 两字段恒定输出（即便为空），以保证 `decode_any` 能精确还原原值，从而往返
/// 一致（R4.2）。type_url 以 UTF-8 编码（复用 `string_to_bytes`）。
pub fn encode_any(any : AnyValue) -> Bytes {
  let buf : Array[Byte] = []
  // field 1：type_url（string → UTF-8 字节，长度前缀）。
  let url_bytes = string_to_bytes(any.type_url)
  write_varint(buf, any_len_tag(ANY_FIELD_TYPE_URL))
  write_varint(buf, url_bytes.length().to_uint64())
  for i in 0..<url_bytes.length() {
    buf.push(url_bytes[i])
  }
  // field 2：value（不透明字节，长度前缀）。
  write_varint(buf, any_len_tag(ANY_FIELD_VALUE))
  write_varint(buf, any.value.length().to_uint64())
  for i in 0..<any.value.length() {
    buf.push(any.value[i])
  }
  Bytes::from_array(buf)
}

///|
/// 从 `start` 处读取一个 `Len` 字段的负载：先读 varint 长度，再截取该长度的字节
/// 切片，返回 `(切片, 下一索引)`。长度以无符号比较防 Int 溢出，越界 / 截断返回
/// 含偏移的 `DecodeError`。
fn read_len_payload(
  bytes : Bytes,
  start : Int,
) -> Result[(Bytes, Int), DecodeError] {
  let (len64, after_len) = match read_varint(bytes, start) {
    Ok(pair) => pair
    Err(e) => return Err(e)
  }
  let remaining = (bytes.length() - after_len).to_uint64()
  if len64 > remaining {
    return Err(UnexpectedEof(offset=after_len))
  }
  let len = len64.to_int()
  let slice : Array[Byte] = []
  for i in 0..<len {
    slice.push(bytes[after_len + i])
  }
  Ok((Bytes::from_array(slice), after_len + len))
}

///|
/// 将 `google.protobuf.Any` 形态的字节序列解码为 `AnyValue`，与 `encode_any`
/// 构成对偶（R4.2 往返）。
///
/// 按 wire tag 扫描全部字段：field 1（Len）→ type_url（UTF-8 还原），field 2
/// （Len）→ value（原始字节）。proto3 默认值语义下缺失字段取默认（空串 / 空
/// 字节），重复出现以最后一次为准。遇到非预期字段号或非 `Len` wire 类型返回
/// 描述性 `DecodeError`，不构造部分对象。
pub fn decode_any(bytes : Bytes) -> Result[AnyValue, DecodeError] {
  let mut type_url = ""
  let mut value : Bytes = Bytes::from_array([])
  let mut pos = 0
  while pos < bytes.length() {
    let tag_start = pos
    let (tag, after_tag) = match read_varint(bytes, pos) {
      Ok(pair) => pair
      Err(e) => return Err(e)
    }
    let number = (tag >> 3).to_int()
    let wire_code = (tag & 0x7UL).to_int()
    // Any 的两个字段均为 Len wire 类型；其余 wire 类型视为畸形输入。
    if wire_code != WireType::Len.code() {
      return Err(InvalidWireType(offset=tag_start, tag~))
    }
    let (payload, next) = match read_len_payload(bytes, after_tag) {
      Ok(pair) => pair
      Err(e) => return Err(e)
    }
    pos = next
    if number == ANY_FIELD_TYPE_URL {
      type_url = bytes_to_string(payload)
    } else if number == ANY_FIELD_VALUE {
      value = payload
    } else {
      // 非 Any 定义的字段号：拒绝，避免静默吞掉未知结构。
      return Err(InvalidFieldNumber(offset=tag_start, number~))
    }
  }
  Ok({ type_url, value })
}

// ───────────────────────────── 流式编解码 ────────────────────────────────

///|
/// 流式写入端：以可增长的 `Array[Byte]` 累积字节，最终 `to_bytes` 一次性物化。
/// 多次 `encode_to` 把各消息的「长度前缀帧」顺序追加到同一 sink。
///
/// 字段 `buf` 经 `push` 原地增长（不整体重绑定），故无需 `mut` 修饰。
pub struct ByteSink {
  buf : Array[Byte]
}

///|
/// 创建空的 `ByteSink`。
pub fn ByteSink::new() -> ByteSink {
  { buf: [] }
}

///|
/// 将已累积的字节物化为不可变 `Bytes`（不清空内部缓冲，可继续写入）。
pub fn ByteSink::to_bytes(self : ByteSink) -> Bytes {
  Bytes::from_array(self.buf)
}

///|
/// 当前已累积的字节数（O(1)）。
pub fn ByteSink::len(self : ByteSink) -> Int {
  self.buf.length()
}

///|
/// 流式读取端：持有只读字节序列与可推进的游标 `pos`。每次 `decode_from` 从
/// `pos` 处读出一帧并把游标前移到该帧末尾，从而支持顺序读取多条消息。
pub struct ByteSource {
  data : Bytes
  mut pos : Int
}

///|
/// 由字节序列创建读取端，游标初始指向 0。
pub fn ByteSource::new(data : Bytes) -> ByteSource {
  { data, pos: 0 }
}

///|
/// 当前游标位置（已消费的字节数）。
pub fn ByteSource::position(self : ByteSource) -> Int {
  self.pos
}

///|
/// 是否已读到末尾（无剩余字节）。
pub fn ByteSource::is_exhausted(self : ByteSource) -> Bool {
  self.pos >= self.data.length()
}

///|
/// 将一条类型化消息以「长度前缀帧」写入 `sink`（R4.5）。
///
/// 委派既有 `encode_typed`（模式驱动编码）得到负载字节，随后写入
/// `varint(负载长度) ++ 负载`。长度前缀使同一字节流可承载多条消息并精确定界，
/// 与 `decode_from` 构成对偶。编码失败原样透传 `DecodeError`，此时不向 sink
/// 写入任何字节（先编码、成功后才追加）。
pub fn encode_to(
  sink : ByteSink,
  schema : ProtoSchema,
  msg_name : String,
  msg : TypedMessage,
) -> Result[Unit, DecodeError] {
  match encode_typed(schema, msg_name, msg) {
    Ok(payload) => {
      // 仅在编码成功后才修改 sink：先写长度前缀，再写负载。
      write_varint(sink.buf, payload.length().to_uint64())
      for i in 0..<payload.length() {
        sink.buf.push(payload[i])
      }
      Ok(())
    }
    Err(e) => Err(e)
  }
}

///|
/// 从 `source` 当前游标读出一帧并解码为类型化消息（R4.6）。
///
/// 先读长度前缀 varint，再截取该长度的负载切片，把游标推进到该帧末尾，随后
/// 委派既有 `decode_typed` 解码。与 `encode_to` 构成对偶：
/// `decode_from(encode_to(m)) == m`。越界 / 截断 / 畸形 varint 返回含偏移的
/// `DecodeError`，且不推进游标越过非法边界。
pub fn decode_from(
  source : ByteSource,
  schema : ProtoSchema,
  msg_name : String,
) -> Result[TypedMessage, DecodeError] {
  match read_len_payload(source.data, source.pos) {
    Ok((payload, next)) => {
      source.pos = next
      decode_typed(schema, msg_name, payload)
    }
    Err(e) => Err(e)
  }
}
