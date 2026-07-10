// wire.mbt —— protobuf wire format 编解码（高层接口 encode / decode）。
//
// 在 wire 粒度（tag = 字段号<<3 | wire 类型）上做 varint / 定长 / 长度前缀的
// 通用编解码，使内存 `Message`（字段记录序列）与字节序列可往返。
//
// 任务 7.2（本任务）：在 7.1 通用桩的基础上**巩固并加固** protobuf wire format
// 的编解码，使其覆盖四类 wire 类型的正确编解码并加强边界健壮性：
//   * Varint（0）——base-128 变长整数，支持到 64 位最大值（最长 10 字节）；
//   * I64（1）——定长 8 字节小端；
//   * I32（5）——定长 4 字节小端；
//   * Len（2）——长度前缀，长度以无符号比较防 Int 溢出，含空字节序列。
// 同时维持字段顺序、空消息、超大字段号等边界的正确往返。
//
// 明确的范围边界：模式驱动（schema-directed）的**类型化**编解码——按
// `Schema` 把字段号映射为命名字段、解释 sint 的 zigzag、bool / enum、repeated
// 与 packed、默认值省略等——属于后续子 spec 迭代，本任务不实现。
//
// 关键契约（Requirement 9.4）：`decode` 遇到任何非法字节时，返回**含出错字节
// 偏移**的 `DecodeError`，并且**不返回部分构造的 `Message`**——所有字段先收集
// 到局部数组，仅当整段字节合法扫描至末尾才构造并返回 `Message`。

///|
/// 向字节累加器写入一个 base-128 varint（小端、每字节高位为续位标志）。
fn write_varint(buf : Array[Byte], value : UInt64) -> Unit {
  let mut v = value
  while v >= 0x80UL {
    buf.push((((v & 0x7fUL) | 0x80UL) & 0xffUL).to_int().to_byte())
    v = v >> 7
  }
  buf.push((v & 0xffUL).to_int().to_byte())
}

///|
/// 写入定长小端字节（`width` 取 4 或 8），低位在前。
fn write_fixed(buf : Array[Byte], value : UInt64, width : Int) -> Unit {
  let mut v = value
  for _i in 0..<width {
    buf.push((v & 0xffUL).to_int().to_byte())
    v = v >> 8
  }
}

///|
/// 将内存消息对象编码为 protobuf wire format 字节序列（Requirement 9.1）。
///
/// 骨架阶段按字段记录的 wire 类型逐条编码：先写 tag（字段号<<3 | wire），再写
/// 取值（varint / 定长 / 长度前缀 + 原始字节）。模式化类型编码见任务 7.2。
pub fn encode(msg : Message) -> Bytes {
  let buf : Array[Byte] = []
  encode_fields(buf, msg.fields)
  Bytes::from_array(buf)
}

///|
/// 将字段记录序列逐条写入缓冲；分组（VGroup）以 SGroup..EGroup
/// 定界递归写入子字段。
fn encode_fields(buf : Array[Byte], fields : Array[FieldEntry]) -> Unit {
  for entry in fields {
    let wt = entry.value.wire_type()
    let tag = (entry.number.to_uint64() << 3) | wt.code().to_uint64()
    write_varint(buf, tag)
    match entry.value {
      VVarint(v) => write_varint(buf, v)
      VI64(v) => write_fixed(buf, v, 8)
      VI32(v) => write_fixed(buf, v.to_uint64(), 4)
      VBytes(bytes) => {
        write_varint(buf, bytes.length().to_uint64())
        for i in 0..<bytes.length() {
          buf.push(bytes[i])
        }
      }
      VGroup(sub) => {
        encode_fields(buf, sub)
        let end_tag = (entry.number.to_uint64() << 3) |
          WireType::EGroup.code().to_uint64()
        write_varint(buf, end_tag)
      }
    }
  }
}

///|
/// 从 `start` 处读取一个 base-128 varint，返回 `(值, 下一索引)`。
///
/// 失败契约：起始即越界 → `UnexpectedEof(start)`；续位字节缺失（中途到末尾）
/// → `UnexpectedEof`；超过 10 个字节仍未终止 → `MalformedVarint(start)`。
fn read_varint(
  bytes : Bytes,
  start : Int,
) -> Result[(UInt64, Int), DecodeError] {
  if start >= bytes.length() {
    return Err(UnexpectedEof(offset=start))
  }
  let mut result : UInt64 = 0UL
  let mut shift = 0
  let mut idx = start
  let mut count = 0
  while idx < bytes.length() {
    let b = bytes[idx].to_int().to_uint64()
    result = result | ((b & 0x7fUL) << shift)
    idx = idx + 1
    count = count + 1
    if (b & 0x80UL) == 0UL {
      return Ok((result, idx))
    }
    if count >= 10 {
      return Err(MalformedVarint(offset=start))
    }
    shift = shift + 7
  }
  // 续位标志仍置位却已到末尾：截断的 varint。
  Err(UnexpectedEof(offset=start))
}

///|
/// 从 `start` 处读取 `width`（4 或 8）字节定长小端整数，返回 `(值, 下一索引)`。
fn read_fixed(
  bytes : Bytes,
  start : Int,
  width : Int,
) -> Result[(UInt64, Int), DecodeError] {
  if start + width > bytes.length() {
    return Err(UnexpectedEof(offset=start))
  }
  let mut result : UInt64 = 0UL
  for i in 0..<width {
    let b = bytes[start + i].to_int().to_uint64()
    result = result | (b << (8 * i))
  }
  Ok((result, start + width))
}

///|
/// 将 wire format 字节序列按模式解码为内存消息对象（Requirement 9.2）。
///
/// 骨架阶段做 wire 粒度的通用扫描（不依赖 `schema` 的类型信息——模式化类型解码
/// 属任务 7.2，故此处保留 `schema` 形参以锁定接口契约）。任何非法字节都使本
/// 函数以 `Err(DecodeError)`（含出错字节偏移）返回，且**绝不返回部分构造的
/// `Message`**：字段先收集到局部 `entries`，仅当合法扫描至末尾才构造消息
/// （Requirement 9.4）。
pub fn decode(bytes : Bytes, schema : Schema) -> Result[Message, DecodeError] {
  ignore(schema)
  match decode_fields(bytes, 0, -1) {
    Ok((entries, end_pos)) => {
      ignore(end_pos)
      Ok(Message::from_fields(entries))
    }
    Err(e) => Err(e)
  }
}

///|
/// 自 `start` 扫描字段直至输入末尾（`group_number < 0`）或遇到字段号
/// 匹配的 EGroup 定界（处于分组内）；返回（字段序列，下一偏移）。
/// SGroup 递归下降；孤立 / 号不匹配的 EGroup、未闭合的分组均报错。
fn decode_fields(
  bytes : Bytes,
  start : Int,
  group_number : Int,
) -> Result[(Array[FieldEntry], Int), DecodeError] {
  let entries : Array[FieldEntry] = []
  let mut pos = start
  while pos < bytes.length() {
    let tag_start = pos
    let (tag, after_tag) = match read_varint(bytes, pos) {
      Ok(pair) => pair
      Err(e) => return Err(e)
    }
    let number = (tag >> 3).to_int()
    if number <= 0 {
      return Err(InvalidFieldNumber(offset=tag_start, number~))
    }
    let wire_code = (tag & 0x7UL).to_int()
    let wt = match WireType::from_code(wire_code) {
      Some(w) => w
      None => return Err(InvalidWireType(offset=tag_start, tag~))
    }
    pos = after_tag
    let value = match wt {
      SGroup =>
        match decode_fields(bytes, pos, number) {
          Ok((sub, next)) => {
            pos = next
            FieldValue::VGroup(sub)
          }
          Err(e) => return Err(e)
        }
      EGroup =>
        if group_number == number {
          return Ok((entries, pos))
        } else {
          // 孤立或号不匹配的结束定界：非法。
          return Err(InvalidWireType(offset=tag_start, tag~))
        }
      Varint => {
        let (v, next) = match read_varint(bytes, pos) {
          Ok(pair) => pair
          Err(e) => return Err(e)
        }
        pos = next
        FieldValue::VVarint(v)
      }
      I64 => {
        let (v, next) = match read_fixed(bytes, pos, 8) {
          Ok(pair) => pair
          Err(e) => return Err(e)
        }
        pos = next
        FieldValue::VI64(v)
      }
      I32 => {
        let (v, next) = match read_fixed(bytes, pos, 4) {
          Ok(pair) => pair
          Err(e) => return Err(e)
        }
        pos = next
        FieldValue::VI32(v.to_uint())
      }
      Len => {
        let (len64, after_len) = match read_varint(bytes, pos) {
          Ok(pair) => pair
          Err(e) => return Err(e)
        }
        // 以无符号比较避免 Int 溢出：声明的长度不得超过剩余字节数。
        // `after_len` 由 read_varint 保证落在 [0, length] 内，故 remaining ≥ 0。
        let remaining = (bytes.length() - after_len).to_uint64()
        if len64 > remaining {
          return Err(UnexpectedEof(offset=after_len))
        }
        let len = len64.to_int()
        let slice : Array[Byte] = []
        for i in 0..<len {
          slice.push(bytes[after_len + i])
        }
        pos = after_len + len
        FieldValue::VBytes(Bytes::from_array(slice))
      }
    }
    entries.push({ number, value })
  }
  if group_number >= 0 {
    // 分组未以 EGroup 闭合即到达末尾：截断。
    return Err(UnexpectedEof(offset=pos))
  }
  Ok((entries, pos))
}
