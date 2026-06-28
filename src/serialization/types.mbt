// types.mbt —— Serialization_Framework 的核心数据模型。
//
// 设计依据（design.md §「方向九：Serialization_Framework」核心类型与流水线，
// 以及 §「数据模型 → 跨方向共享：结果与错误模型」）：
//
//   pub fn encode(msg : Message) -> Bytes
//   pub fn decode(bytes : Bytes, schema : Schema) -> Result[Message, DecodeError]
//   pub fn parse_proto(src : String) -> Result[Schema, ParseError]
//   pub fn gen_moonbit(schema : Schema) -> String
//
// 本文件锁定三组数据模型的骨架：
//   1. wire 运行时模型（WireType / FieldValue / FieldEntry / Message）——
//      内存中的消息对象，编解码在其上往返；
//   2. 模式描述模型（FieldType / FieldDef / MessageDef / EnumDef / Schema）——
//      由 `.proto` 解析得到、并驱动代码生成；
//   3. 错误模型（DecodeError / ParseError）—— 均**携带定位信息**：解码错误带
//      字节偏移、解析错误带行列，满足"返回含位置的错误且不产生部分构造对象"。

// ───────────────────────────── wire 运行时模型 ─────────────────────────────

///|
/// protobuf wire 类型（wire type）。
///
/// 对应 protobuf 规范中 tag 低 3 位编码的线格式类别。骨架阶段覆盖四类常用
/// wire 类型；废弃的 group（3 / 4）不在支持范围内。
pub(all) enum WireType {
  Varint // 0：变长整数（int32/int64/uint*/bool/enum/sint*）
  I64 // 1：定长 64 位（fixed64/sfixed64/double）
  Len // 2：长度前缀（string/bytes/嵌套消息/packed repeated）
  I32 // 5：定长 32 位（fixed32/sfixed32/float）
} derive(Eq, Debug)

///|
/// 返回该 wire 类型在 tag 中编码的数值（0/1/2/5）。
pub fn WireType::code(self : WireType) -> Int {
  match self {
    Varint => 0
    I64 => 1
    Len => 2
    I32 => 5
  }
}

///|
/// 由 tag 低 3 位的数值还原 wire 类型；非受支持的取值返回 `None`。
pub fn WireType::from_code(code : Int) -> WireType? {
  match code {
    0 => Some(Varint)
    1 => Some(I64)
    2 => Some(Len)
    5 => Some(I32)
    _ => None
  }
}

///|
/// 字段值（field value）—— wire 层面的、未经模式类型化的原始取值。
///
/// 骨架阶段以"wire 类型"为粒度承载取值；模式驱动的类型化解释（如把
/// `VVarint` 进一步解读为 sint 的 zigzag、bool、enum 等）属于任务 7.2。
pub(all) enum FieldValue {
  VVarint(UInt64) // 来自 Varint：原始变长整数位
  VI64(UInt64) // 来自 I64：原始 8 字节小端位
  VI32(UInt) // 来自 I32：原始 4 字节小端位
  VBytes(Bytes) // 来自 Len：长度前缀的原始字节
} derive(Eq, Debug)

///|
/// 构造一个 Varint 字段值（int*/uint*/bool/enum 的 wire 承载）。
pub fn FieldValue::varint(v : UInt64) -> FieldValue {
  VVarint(v)
}

///|
/// 构造一个定长 64 位字段值（fixed64/sfixed64/double 的 wire 承载）。
pub fn FieldValue::i64(v : UInt64) -> FieldValue {
  VI64(v)
}

///|
/// 构造一个定长 32 位字段值（fixed32/sfixed32/float 的 wire 承载）。
pub fn FieldValue::i32(v : UInt) -> FieldValue {
  VI32(v)
}

///|
/// 构造一个长度前缀字段值（string/bytes/嵌套消息的 wire 承载）。
pub fn FieldValue::bytes(b : Bytes) -> FieldValue {
  VBytes(b)
}

///|
/// 返回该字段值对应的 wire 类型。
pub fn FieldValue::wire_type(self : FieldValue) -> WireType {
  match self {
    VVarint(_) => Varint
    VI64(_) => I64
    VI32(_) => I32
    VBytes(_) => Len
  }
}

///|
/// 一条已编解码的字段记录：字段号 `number` + 取值 `value`。
pub(all) struct FieldEntry {
  number : Int
  value : FieldValue
} derive(Eq, Debug)

///|
/// 构造一条字段记录。
pub fn FieldEntry::new(number : Int, value : FieldValue) -> FieldEntry {
  { number, value }
}

///|
/// 内存中的消息对象（in-memory message）。
///
/// design.md 中 `encode(msg : Message)` / `decode(...) -> Message` 的承载类型。
/// 骨架以"字段记录序列"表示，保留 wire 顺序；模式化的命名字段视图属于 7.2。
pub(all) struct Message {
  fields : Array[FieldEntry]
} derive(Eq, Debug)

///|
/// 构造空消息（无字段）。
pub fn Message::empty() -> Message {
  { fields: [] }
}

///|
/// 由字段记录数组构造消息。
pub fn Message::from_fields(fields : Array[FieldEntry]) -> Message {
  { fields, }
}

// ───────────────────────────── 模式描述模型 ──────────────────────────────

///|
/// 字段类型（schema 层）。骨架覆盖 proto3 常用标量与对消息/枚举的引用。
pub(all) enum FieldType {
  TInt32
  TInt64
  TUInt32
  TUInt64
  TBool
  TString
  TBytes
  TMessage(String) // 引用某消息类型（按名）
  TEnum(String) // 引用某枚举类型（按名）
} derive(Eq, Debug)

///|
/// 字段定义：名称 / 字段号 / 类型 / 是否 repeated。
pub(all) struct FieldDef {
  name : String
  number : Int
  ftype : FieldType
  repeated : Bool
} derive(Eq, Debug)

///|
/// 消息定义：名称 + 字段定义序列。骨架阶段 `parse_proto` 仅填充名称，字段
/// 的完整解析在后续子 spec 迭代。
pub(all) struct MessageDef {
  name : String
  fields : Array[FieldDef]
} derive(Eq, Debug)

///|
/// 枚举定义：名称 + `(标识符, 取值)` 序列。
pub(all) struct EnumDef {
  name : String
  values : Array[(String, Int)]
} derive(Eq, Debug)

///|
/// 模式描述（schema）—— `.proto` 解析产物，驱动编解码与代码生成。
pub(all) struct Schema {
  messages : Array[MessageDef]
  enums : Array[EnumDef]
} derive(Eq, Debug)

///|
/// 构造空模式。
pub fn Schema::empty() -> Schema {
  { messages: [], enums: [] }
}

// ─────────────────────────────── 错误模型 ────────────────────────────────

///|
/// 解码错误（decode error）—— **每个变体均携带出错字节偏移 `offset`**，以满足
/// Requirement 9.4「返回包含出错字节偏移的解码错误，且不产生部分构造的对象」。
pub(all) enum DecodeError {
  UnexpectedEof(offset~ : Int) // 在 offset 处输入意外结束
  MalformedVarint(offset~ : Int) // 起始于 offset 的 varint 编码非法（如超长/截断）
  InvalidWireType(offset~ : Int, tag~ : UInt64) // offset 处 tag 的 wire 类型非法
  InvalidFieldNumber(offset~ : Int, number~ : Int) // offset 处字段号非法（如 0）
} derive(Eq, Debug)

///|
/// 公开错误类型的 `Show` 委托其 `Debug` 结构化表示（与历史 `derive` 输出一致），
/// 供错误信息展示 / 字符串插值使用；调试比较走 `Debug`。
pub impl Show for DecodeError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// 统一取出解码错误的出错字节偏移（供调用方与测试以稳定方式断言定位）。
pub fn DecodeError::offset(self : DecodeError) -> Int {
  match self {
    UnexpectedEof(offset~) => offset
    MalformedVarint(offset~) => offset
    InvalidWireType(offset~, ..) => offset
    InvalidFieldNumber(offset~, ..) => offset
  }
}

///|
/// `.proto` 解析错误（parse error）—— 携带行列与偏移定位，满足 Requirement 9.6
/// 「返回包含行列位置的解析错误」。`message` 为人类可读的诊断说明。
pub(all) struct ParseError {
  line : Int
  col : Int
  offset : Int
  message : String
} derive(Eq, Debug)

///|
/// 公开错误类型的 `Show` 委托其 `Debug` 结构化表示（与历史 `derive` 输出一致）。
pub impl Show for ParseError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// 构造解析错误。
pub fn ParseError::new(
  line : Int,
  col : Int,
  offset : Int,
  message : String,
) -> ParseError {
  { line, col, offset, message }
}

///|
/// 由 @parser_combinator 的位置 `Pos` 构造解析错误，复用统一的定位模型。
pub fn ParseError::at(
  pos : @parser_combinator.Pos,
  message : String,
) -> ParseError {
  { line: pos.line, col: pos.col, offset: pos.offset, message }
}
