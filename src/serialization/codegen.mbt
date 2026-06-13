// codegen.mbt —— 由模式生成 MoonBit 代码（高层接口 gen_moonbit）。
//
// 对应任务 7.1 的 gen_moonbit 高层接口桩。骨架阶段为每个消息定义产出一个
// 占位的 MoonBit 结构体声明骨架；字段级类型映射、配套编解码代码生成属于
// 后续子 spec 迭代（Requirement 9.7 的完整实现）。

///|
/// 将 schema 字段类型映射为 MoonBit 类型名（骨架占位映射）。
fn moonbit_type_name(ftype : FieldType) -> String {
  match ftype {
    TInt32 => "Int"
    TInt64 => "Int64"
    TUInt32 => "UInt"
    TUInt64 => "UInt64"
    TBool => "Bool"
    TString => "String"
    TBytes => "Bytes"
    TMessage(name) => name
    TEnum(name) => name
  }
}

///|
/// 由模式生成对应的 MoonBit 类型定义代码（Requirement 9.7）。
///
/// 骨架阶段：为每个 `MessageDef` 生成一个带已知字段（若有）的 `pub struct`
/// 声明骨架。完整的字段类型推导与编解码代码生成在后续迭代补全。
pub fn gen_moonbit(schema : Schema) -> String {
  let mut out = "// 由 gen_moonbit 生成（骨架）—— 请勿手工编辑\n"
  for msg in schema.messages {
    out = out + "\npub struct \{msg.name} {\n"
    for field in msg.fields {
      let base = moonbit_type_name(field.ftype)
      let ty = if field.repeated { "Array[\{base}]" } else { base }
      out = out + "  \{field.name} : \{ty}\n"
    }
    out = out + "} derive(Eq, Show)\n"
  }
  out
}
