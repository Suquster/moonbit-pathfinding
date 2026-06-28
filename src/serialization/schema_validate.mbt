// schema_validate.mbt —— 模式校验（旗舰深化，旁路新增，R4）。
//
// 设计依据（design.md §4.6「模式校验 SchemaError / validate_schema」）：在编解码
// 前对富模式做一致性校验，尽早发现字段号冲突、保留号违例与悬空类型引用等错误
// 并定位之。`SchemaError` 为**全新语义**（既有错误模型不含模式校验），单列新
// 类型并自由携带定位；既有 `DecodeError`/`ParseError` 不扩容、不改写。

///|
/// 模式校验诊断（携带定位信息）。
pub enum SchemaError {
  FieldNumberOutOfRange(message~ : String, field~ : String, number~ : Int)
  DuplicateFieldNumber(message~ : String, number~ : Int)
  ReservedConflict(message~ : String, which~ : String) // 号或名命中 reserved
  UnresolvedTypeRef(message~ : String, field~ : String, ref_~ : String)
  EnumFirstValueNonZero(enum_~ : String, first~ : Int)
} derive(Eq, Show)

///|
/// proto3 合法字段号下界（含）。
let field_number_min : Int = 1

///|
/// proto3 合法字段号上界（含）：2^29 - 1。
let field_number_max : Int = 536870911

///|
/// protobuf 实现保留区间下界（含）。
let field_number_reserved_lo : Int = 19000

///|
/// protobuf 实现保留区间上界（含）。
let field_number_reserved_hi : Int = 19999

///|
/// 字段号是否落在 proto3 合法范围：`[1, 536870911]` 且 ∉ `[19000, 19999]`。
fn field_number_valid(n : Int) -> Bool {
  n >= field_number_min &&
  n <= field_number_max &&
  !(n >= field_number_reserved_lo && n <= field_number_reserved_hi)
}

///|
/// 字段号是否命中某消息的保留区间。
fn hits_reserved_number(msg : ProtoMessage, n : Int) -> Bool {
  for r in msg.reserved_numbers {
    if n >= r.lo && n <= r.hi {
      return true
    }
  }
  false
}

///|
/// 字段名是否命中某消息的保留名。
fn hits_reserved_name(msg : ProtoMessage, name : String) -> Bool {
  for r in msg.reserved_names {
    if r == name {
      return true
    }
  }
  false
}

///|
/// 类型引用（`PMessage`/`PEnum`）是否可在 schema 中按限定名解析。其余标量恒可解析。
fn type_ref_resolves(schema : ProtoSchema, t : ProtoType) -> Bool {
  match t {
    PMessage(n) =>
      match schema.message(n) {
        Some(_) => true
        None => false
      }
    PEnum(n) =>
      match schema.enum_def(n) {
        Some(_) => true
        None => false
      }
    _ => true
  }
}

///|
/// 全量校验富模式（R4.1–4.6）。
///
/// 校验项：① 每字段号 ∈ `[1, 536870911]` 且 ∉ `[19000, 19999]`；② 同消息字段号
/// 唯一（含 map 字段号）；③ 字段号/名不得命中本消息 `reserved`；④ `PMessage`/
/// `PEnum` 引用按限定名可解析；⑤ proto3 枚举首值须为 0。一次性收集全部诊断：
/// 通过返回 `Ok(())`；否则返回 `Err(Array[SchemaError])`（R4.6）。
pub fn validate_schema(
  schema : ProtoSchema,
) -> Result[Unit, Array[SchemaError]] {
  let errors : Array[SchemaError] = []

  // 枚举首值须为 0（R4.5）。
  for e in schema.enums {
    if e.values.length() > 0 {
      let (_, first) = e.values[0]
      if first != 0 {
        errors.push(EnumFirstValueNonZero(enum_=e.name, first~))
      }
    }
  }

  // 逐消息校验字段号 / 引用 / reserved。
  for m in schema.messages {
    let seen : Map[Int, Bool] = {}
    // 常规字段（含 oneof 成员）。
    for f in m.fields {
      if !(field_number_valid(f.number)) {
        errors.push(
          FieldNumberOutOfRange(message=m.name, field=f.name, number=f.number),
        )
      }
      match seen.get(f.number) {
        Some(_) =>
          errors.push(DuplicateFieldNumber(message=m.name, number=f.number))
        None => seen[f.number] = true
      }
      if hits_reserved_number(m, f.number) {
        errors.push(
          ReservedConflict(
            message=m.name,
            which="number " + f.number.to_string(),
          ),
        )
      }
      if hits_reserved_name(m, f.name) {
        errors.push(ReservedConflict(message=m.name, which="name " + f.name))
      }
      if !(type_ref_resolves(schema, f.ptype)) {
        let ref_ = match f.ptype {
          PMessage(n) => n
          PEnum(n) => n
          _ => ""
        }
        errors.push(UnresolvedTypeRef(message=m.name, field=f.name, ref_~))
      }
    }
    // map 字段：字段号同样参与唯一性与范围校验，键/值类型引用须可解析。
    for mp in m.maps {
      if !(field_number_valid(mp.number)) {
        errors.push(
          FieldNumberOutOfRange(message=m.name, field=mp.name, number=mp.number),
        )
      }
      match seen.get(mp.number) {
        Some(_) =>
          errors.push(DuplicateFieldNumber(message=m.name, number=mp.number))
        None => seen[mp.number] = true
      }
      if hits_reserved_number(m, mp.number) {
        errors.push(
          ReservedConflict(
            message=m.name,
            which="number " + mp.number.to_string(),
          ),
        )
      }
      if !(type_ref_resolves(schema, mp.value)) {
        let ref_ = match mp.value {
          PMessage(n) => n
          PEnum(n) => n
          _ => ""
        }
        errors.push(UnresolvedTypeRef(message=m.name, field=mp.name, ref_~))
      }
    }
  }
  if errors.length() == 0 {
    Ok(())
  } else {
    Err(errors)
  }
}
