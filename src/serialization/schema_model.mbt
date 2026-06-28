// schema_model.mbt —— 富模式模型（旗舰深化，旁路新增）。
//
// 设计依据（design.md §4.1「富模式模型 ProtoSchema」，R3/R1/R6）：既有
// `FieldType`/`Schema`（types.mbt，冻结）不区分 sint（zigzag）、float/double、
// fixed/sfixed，也无 oneof/map/嵌套/reserved。本文件新增**富模式模型**承载完整
// proto3 类型信息，并提供向下投影桥 `ProtoSchema::to_legacy` 以桥接既有骨架。
//
// 严格旁路扩展：本文件不修改 types.mbt 任何既有声明；新增类型全部 derive(Eq, Debug)。

// ───────────────────────────── 完整 proto3 字段类型 ─────────────────────────

///|
/// 完整 proto3 字段类型（含 wire 编码语义区分）。
///
/// 既有 `FieldType` 做不到的区分（这正是新增富模型的根因）：
///   * sint 与普通 int（前者 zigzag）；
///   * float/double（定长浮点）与 fixed/sfixed（定长整数）。
pub(all) enum ProtoType {
  PInt32 // 普通 varint
  PInt64
  PUInt32
  PUInt64
  PSInt32 // zigzag varint
  PSInt64
  PFixed32 // 定长无符号（I32 / I64）
  PFixed64
  PSFixed32 // 定长有符号（I32 / I64）
  PSFixed64
  PFloat // 定长浮点（I32）
  PDouble // 定长浮点（I64）
  PBool
  PString
  PBytes
  PMessage(String) // 引用消息（限定名）
  PEnum(String) // 引用枚举（限定名）
} derive(Eq, Debug)

///|
/// 字段标签：proto3 默认（singular）、repeated、或属于某 oneof 互斥组。
pub(all) enum FieldLabel {
  LSingular
  LRepeated(packed~ : Bool) // packed 默认对数值标量为 true
  LOneof(group~ : String)
} derive(Eq, Debug)

///|
/// 字段选项（原样保留 `name`/`value`，不解释语义；如 `[packed=true]`）。
pub(all) struct FieldOption {
  name : String
  value : String
} derive(Eq, Debug)

///|
/// 字段定义（富模型）：名称 / 字段号 / 完整类型 / 标签 / 选项序列。
pub(all) struct ProtoField {
  name : String
  number : Int
  ptype : ProtoType
  label : FieldLabel
  options : Array[FieldOption]
} derive(Eq, Debug)

///|
/// 保留字段号区间（闭区间；单个号时 `lo == hi`）。
pub(all) struct ReservedRange {
  lo : Int
  hi : Int
} derive(Eq, Debug)

///|
/// map<K, V> 条目（wire 上等价于 `repeated` 的 `{key=1, value=2}` 条目消息）。
pub(all) struct MapEntry {
  name : String
  number : Int
  key : ProtoType // 仅允许整型 / bool / string
  value : ProtoType
} derive(Eq, Debug)

///|
/// oneof 互斥组：名称 + 成员字段号序列（成员的字段定义存于 message.fields，
/// 其 label 为 `LOneof(group~)`）。
pub(all) struct OneofDef {
  name : String
  members : Array[Int]
} derive(Eq, Debug)

///|
/// 消息定义（富模型）。`name` 为限定名（嵌套以 '.' 连接）。
pub(all) struct ProtoMessage {
  name : String
  fields : Array[ProtoField]
  maps : Array[MapEntry]
  oneofs : Array[OneofDef]
  reserved_numbers : Array[ReservedRange]
  reserved_names : Array[String]
  nested_messages : Array[String] // 嵌套消息限定名（登记于顶层 messages）
  nested_enums : Array[String]
} derive(Eq, Debug)

///|
/// 富模式：含嵌套、按限定名唯一登记的消息序列 + 枚举（复用既有 `EnumDef`）。
pub(all) struct ProtoSchema {
  messages : Array[ProtoMessage]
  enums : Array[EnumDef]
} derive(Eq, Debug)

///|
/// 构造空富模式。
pub fn ProtoSchema::empty() -> ProtoSchema {
  { messages: [], enums: [] }
}

///|
/// 按限定名查找消息定义；未找到返回 `None`。
pub fn ProtoSchema::message(self : ProtoSchema, name : String) -> ProtoMessage? {
  for m in self.messages {
    if m.name == name {
      return Some(m)
    }
  }
  None
}

///|
/// 按限定名查找枚举定义；未找到返回 `None`。
pub fn ProtoSchema::enum_def(self : ProtoSchema, name : String) -> EnumDef? {
  for e in self.enums {
    if e.name == name {
      return Some(e)
    }
  }
  None
}

///|
/// 将富类型投影为既有骨架 `FieldType`（向下投影规则，见 design.md §4.1）。
///
/// 与既有 `parse_proto`（proto_parser.mbt 的 `field_type_of`）在共同子集上的
/// 产物一致：sint*/sfixed*/fixed* → 既有 `TInt*`；uint* → `TUInt*`。
/// float/double 既有模型无对应标量，按定长宽度投影为最接近的整数占位
/// （`PFloat → TInt32`、`PDouble → TInt64`），仅用于桥接，不参与类型化语义。
fn proto_type_to_legacy(t : ProtoType) -> FieldType {
  match t {
    PInt32 | PSInt32 | PSFixed32 | PFixed32 | PFloat => TInt32
    PInt64 | PSInt64 | PSFixed64 | PFixed64 | PDouble => TInt64
    PUInt32 => TUInt32
    PUInt64 => TUInt64
    PBool => TBool
    PString => TString
    PBytes => TBytes
    PMessage(n) => TMessage(n)
    PEnum(n) => TEnum(n)
  }
}

///|
/// 向下投影到既有骨架 `Schema`（用于桥接既有 API 与差分验证）。
///
/// 投影规则：常规字段保留名/号，类型经 `proto_type_to_legacy` 投影，`repeated`
/// 由 `LRepeated` 标签决定；map 字段展平为指向合成条目消息的 repeated 字段；
/// oneof 成员（其字段定义已在 `fields` 中）按普通字段投影。该投影与既有
/// `parse_proto` 在共同子集上的产物一致，故既有调用方无感。
pub fn ProtoSchema::to_legacy(self : ProtoSchema) -> Schema {
  let messages : Array[MessageDef] = []
  for m in self.messages {
    let fields : Array[FieldDef] = []
    for f in m.fields {
      let repeated = match f.label {
        LRepeated(..) => true
        _ => false
      }
      fields.push({
        name: f.name,
        number: f.number,
        ftype: proto_type_to_legacy(f.ptype),
        repeated,
      })
    }
    for mp in m.maps {
      // map 字段展平为指向合成条目消息的 repeated 字段（wire 等价）。
      fields.push({
        name: mp.name,
        number: mp.number,
        ftype: TMessage(m.name + "." + mp.name + "Entry"),
        repeated: true,
      })
    }
    messages.push({ name: m.name, fields })
  }
  { messages, enums: self.enums }
}
