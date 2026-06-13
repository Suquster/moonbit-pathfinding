// codegen_full.mbt —— 完整代码生成（旗舰深化，旁路新增，R6）。
//
// 设计依据（design.md §4.8「完整代码生成 gen_moonbit_full」）：既有
// `gen_moonbit`（codegen.mbt）冻结（结构体骨架）。本文件新增 `gen_moonbit_full`，
// 由富模式产出带全部字段的 `pub struct`（含 repeated → `Array[元素类型]`，R6.2）
// 与**配套编解码函数**，方法体委托共享类型化编解码（`encode_typed`/`decode_typed`）
// 以保证与库语义一致（R6.3）。生成的委托函数引用库内真实函数，可被工具链编译
// （R6.4）；其往返性质由所委托的类型化模型保证（R6.5，正确性属性 9）。

///|
/// 将富 proto 类型映射为生成代码中的 MoonBit 类型名（R6.1）。
fn moonbit_full_type(t : ProtoType) -> String {
  match t {
    PInt32 | PSInt32 | PSFixed32 => "Int"
    PInt64 | PSInt64 | PSFixed64 => "Int64"
    PUInt32 | PFixed32 => "UInt"
    PUInt64 | PFixed64 => "UInt64"
    PFloat => "Float"
    PDouble => "Double"
    PBool => "Bool"
    PString => "String"
    PBytes => "Bytes"
    PMessage(n) => pg_simple_name(n)
    PEnum(_) => "Int" // 枚举以序数（Int）承载
  }
}

///|
/// 由富模式生成 MoonBit 代码：每消息一个带字段的 `pub struct` + 委托编解码函数。
///
/// 结构体字段类型按 `moonbit_full_type` 映射，repeated → `Array[元素类型]`
/// （R6.1/6.2）；每消息配套 `<Name>_encode`/`<Name>_decode` 委托
/// `encode_typed`/`decode_typed`（R6.3），二者互逆（R6.5）。
pub fn gen_moonbit_full(schema : ProtoSchema) -> String {
  let mut out = "// 由 gen_moonbit_full 生成 —— 请勿手工编辑\n"
  out = out +
    "// 结构体提供类型化视图；编解码委托共享 encode_typed / decode_typed。\n"
  for m in schema.messages {
    let sname = pg_simple_name(m.name)
    // 结构体定义（R6.1 / R6.2）。
    out = out + "\npub struct " + sname + " {\n"
    for f in m.fields {
      let base = moonbit_full_type(f.ptype)
      let ty = match f.label {
        LRepeated(..) => "Array[" + base + "]"
        _ => base
      }
      out = out + "  " + f.name + " : " + ty + "\n"
    }
    for mp in m.maps {
      out = out +
        "  " +
        mp.name +
        " : Array[(" +
        moonbit_full_type(mp.key) +
        ", " +
        moonbit_full_type(mp.value) +
        ")]\n"
    }
    out = out + "} derive(Eq, Show)\n"
    // 配套编解码函数，委托共享类型化模型（R6.3）。
    out = out +
      "\npub fn " +
      sname +
      "_encode(schema : ProtoSchema, msg : TypedMessage) -> Result[Bytes, DecodeError] {\n"
    out = out + "  encode_typed(schema, \"" + m.name + "\", msg)\n}\n"
    out = out +
      "\npub fn " +
      sname +
      "_decode(schema : ProtoSchema, bytes : Bytes) -> Result[TypedMessage, DecodeError] {\n"
    out = out + "  decode_typed(schema, \"" + m.name + "\", bytes)\n}\n"
  }
  out
}
