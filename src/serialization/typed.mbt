// typed.mbt —— 模式驱动的类型化取值模型与编解码（旗舰深化，旁路新增，R1）。
//
// 设计依据（design.md §4.4「类型化取值模型与编解码」）：在既有 wire 粒度通用
// 编解码（wire.mbt，冻结）之上，按 `ProtoSchema` 把字段号映射为命名字段，正确
// 解释 sint 的 zigzag、bool/enum、定长 float/double/fixed、string/bytes、嵌套
// 消息、repeated 聚合、packed 拆包、proto3 默认值省略与未设置字段语义，并保留
// 未知字段。
//
// 关键复用：本文件**直接复用**同包内既有的私有底层读写原语
// （`write_varint`/`write_fixed`/`read_varint`/`read_fixed` 与 `encode`/`decode`），
// 不重复实现 varint/定长/长度前缀逻辑，保证与既有 wire 语义逐字节一致。
//
// 错误模型：wire 类型与声明 `ProtoType` 不符时返回既有 `InvalidWireType`
// （不扩容 `DecodeError` 枚举）；底层非法字节错误（含偏移）由 `decode` 透传。

// ───────────────────────────── 类型化取值模型 ──────────────────────────────

///|
/// 经 `Schema` 解释后的字段取值（模式驱动编解码的目标表示）。
pub(all) enum TypedValue {
  TInt(Int64) // int32/int64/sint32/sint64/sfixed*（有符号，以 Int64 承载）
  TUInt(UInt64) // uint32/uint64/fixed32/fixed64（无符号）
  TBoolV(Bool)
  TEnumV(Int) // 枚举序数
  TFloatV(Float)
  TDoubleV(Double)
  TStringV(String)
  TBytesV(Bytes)
  TMsg(TypedMessage) // 嵌套消息（递归）
  TList(Array[TypedValue]) // repeated（含 packed）
  TMap(Array[(TypedValue, TypedValue)]) // map<K, V>
} derive(Eq, Show)

///|
/// 类型化消息：命名字段取值（仅记录"已显式设置"项）+ 保留的未知字段。
///
/// 取默认值的标量被省略（编码时不写、读取时由 `get_or_default` 按 schema 补默认），
/// 故 `decode_typed(encode_typed(m))` 与 `m` 在内容上相等（默认值不进 `fields`）。
pub(all) struct TypedMessage {
  fields : Map[Int, TypedValue] // 字段号 → 取值
  unknown : Array[FieldEntry] // 未知字段（号/wire/原始取值）原样保留
} derive(Eq, Show)

///|
/// 构造空类型化消息。
pub fn TypedMessage::new() -> TypedMessage {
  { fields: {}, unknown: [] }
}

///|
/// 返回一个在 `number` 处设置 `v` 的新消息（既有字段以浅拷贝保留）。
pub fn TypedMessage::set(
  self : TypedMessage,
  number : Int,
  v : TypedValue,
) -> TypedMessage {
  let nf = self.fields.copy()
  nf[number] = v
  { fields: nf, unknown: self.unknown }
}

///|
/// 读取已设置字段取值；未设置返回 `None`。
pub fn TypedMessage::get(self : TypedMessage, number : Int) -> TypedValue? {
  self.fields.get(number)
}

///|
/// 按 schema 读取：未设置标量返回其类型默认值，未设置 repeated/map 返回空集（R1.8）。
pub fn TypedMessage::get_or_default(
  self : TypedMessage,
  msg : ProtoMessage,
  number : Int,
) -> TypedValue {
  match self.fields.get(number) {
    Some(v) => v
    None => {
      for f in msg.fields {
        if f.number == number {
          return match f.label {
            LRepeated(..) => TList([])
            _ => typed_default(f.ptype)
          }
        }
      }
      for mp in msg.maps {
        if mp.number == number {
          ignore(mp)
          return TMap([])
        }
      }
      TList([])
    }
  }
}

// ───────────────────────────── 类型与默认值辅助 ────────────────────────────

///|
/// 某 `ProtoType` 的类型默认值（proto3 零值语义）。
fn typed_default(t : ProtoType) -> TypedValue {
  match t {
    PInt32 | PInt64 | PSInt32 | PSInt64 | PSFixed32 | PSFixed64 => TInt(0L)
    PUInt32 | PUInt64 | PFixed32 | PFixed64 => TUInt(0UL)
    PBool => TBoolV(false)
    PEnum(_) => TEnumV(0)
    PFloat => TFloatV((0.0 : Float))
    PDouble => TDoubleV(0.0)
    PString => TStringV("")
    PBytes => TBytesV(b"")
    PMessage(_) => TMsg(TypedMessage::new())
  }
}

///|
/// 取值是否为其类型的默认值（用于 proto3 标量默认值省略）。
fn typed_is_default(v : TypedValue) -> Bool {
  match v {
    TInt(n) => n == 0L
    TUInt(u) => u == 0UL
    TBoolV(b) => not(b)
    TEnumV(e) => e == 0
    TFloatV(f) => f == (0.0 : Float)
    TDoubleV(d) => d == 0.0
    TStringV(s) => s == ""
    TBytesV(b) => b.length() == 0
    _ => false
  }
}

///|
/// 该 proto 类型是否为标量（非嵌套消息）；用于默认值省略判定。
fn proto_is_scalar(t : ProtoType) -> Bool {
  match t {
    PMessage(_) => false
    _ => true
  }
}

///|
/// 该 proto 类型是否为可 packed 的数值标量（int/uint/sint/fixed/sfixed/float/
/// double/bool/enum 皆可；string/bytes/message 不可）。
fn proto_is_numeric_scalar(t : ProtoType) -> Bool {
  match t {
    PString | PBytes | PMessage(_) => false
    _ => true
  }
}

///|
/// 该 proto 类型在 wire 上的类别。
fn proto_wire_type(t : ProtoType) -> WireType {
  match t {
    PInt32
    | PInt64
    | PUInt32
    | PUInt64
    | PSInt32
    | PSInt64
    | PBool
    | PEnum(_) => Varint
    PFixed32 | PSFixed32 | PFloat => I32
    PFixed64 | PSFixed64 | PDouble => I64
    PString | PBytes | PMessage(_) => Len
  }
}

// ─────────────────────────── UTF-8 字符串位级编解码 ─────────────────────────

///|
/// 将 `String`（UTF-16 码元）按 UTF-8 编码为字节序列（proto string 的 wire 形态）。
fn string_to_bytes(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for ch in s {
    let cp = ch.to_int()
    if cp < 0x80 {
      buf.push(cp.to_byte())
    } else if cp < 0x800 {
      buf.push((0xC0 | (cp >> 6)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      buf.push((0xE0 | (cp >> 12)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      buf.push((0xF0 | (cp >> 18)).to_byte())
      buf.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  Bytes::from_array(buf)
}

///|
/// 由 UTF-8 字节序列还原 `String`；非法序列按 lossy（U+FFFD）替换以保证终止。
fn bytes_to_string(b : Bytes) -> String {
  let chars : Array[Char] = []
  let n = b.length()
  let mut i = 0
  while i < n {
    let b0 = b[i].to_int()
    if b0 < 0x80 {
      chars.push(Char::from_int(b0))
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 && i + 1 < n {
      let b1 = b[i + 1].to_int()
      chars.push(Char::from_int(((b0 & 0x1F) << 6) | (b1 & 0x3F)))
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < n {
      let b1 = b[i + 1].to_int()
      let b2 = b[i + 2].to_int()
      chars.push(
        Char::from_int(((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)),
      )
      i = i + 3
    } else if (b0 & 0xF8) == 0xF0 && i + 3 < n {
      let b1 = b[i + 1].to_int()
      let b2 = b[i + 2].to_int()
      let b3 = b[i + 3].to_int()
      chars.push(
        Char::from_int(
          ((b0 & 0x07) << 18) |
          ((b1 & 0x3F) << 12) |
          ((b2 & 0x3F) << 6) |
          (b3 & 0x3F),
        ),
      )
      i = i + 4
    } else {
      chars.push(Char::from_int(0xFFFD))
      i = i + 1
    }
  }
  String::from_array(chars)
}

// ─────────────────────────────── 标量编码 ──────────────────────────────────

///|
/// 将一个标量类型化取值编码为单个 wire `FieldValue`（含嵌套消息递归）。
///
/// 类型与取值不符返回 `InvalidWireType`（复用既有变体，不扩容枚举）。
fn encode_scalar_value(
  schema : ProtoSchema,
  t : ProtoType,
  v : TypedValue,
) -> Result[FieldValue, DecodeError] {
  match (t, v) {
    (PInt32, TInt(n)) => Ok(VVarint(n.reinterpret_as_uint64()))
    (PInt64, TInt(n)) => Ok(VVarint(n.reinterpret_as_uint64()))
    (PUInt32, TUInt(u)) => Ok(VVarint(u))
    (PUInt64, TUInt(u)) => Ok(VVarint(u))
    (PSInt32, TInt(n)) => Ok(VVarint(zigzag_encode_32(n.to_int()).to_uint64()))
    (PSInt64, TInt(n)) => Ok(VVarint(zigzag_encode_64(n)))
    (PBool, TBoolV(b)) => Ok(VVarint(if b { 1UL } else { 0UL }))
    (PEnum(_), TEnumV(e)) => Ok(VVarint(e.to_int64().reinterpret_as_uint64()))
    (PFixed32, TUInt(u)) => Ok(VI32(u.to_uint()))
    (PSFixed32, TInt(n)) => Ok(VI32(n.to_int().reinterpret_as_uint()))
    (PFloat, TFloatV(f)) => Ok(VI32(float_to_bits(f)))
    (PFixed64, TUInt(u)) => Ok(VI64(u))
    (PSFixed64, TInt(n)) => Ok(VI64(n.reinterpret_as_uint64()))
    (PDouble, TDoubleV(d)) => Ok(VI64(double_to_bits(d)))
    (PString, TStringV(s)) => Ok(VBytes(string_to_bytes(s)))
    (PBytes, TBytesV(b)) => Ok(VBytes(b))
    (PMessage(name), TMsg(inner)) =>
      match encode_typed(schema, name, inner) {
        Ok(bytes) => Ok(VBytes(bytes))
        Err(e) => Err(e)
      }
    _ => Err(InvalidWireType(offset=0, tag=0UL))
  }
}

///|
/// 把一个数值标量的原始取值写入 packed 载荷缓冲（无 tag）。
fn write_scalar_to_buf(
  schema : ProtoSchema,
  t : ProtoType,
  v : TypedValue,
  buf : Array[Byte],
) -> Result[Unit, DecodeError] {
  match encode_scalar_value(schema, t, v) {
    Ok(VVarint(u)) => {
      write_varint(buf, u)
      Ok(())
    }
    Ok(VI32(u)) => {
      write_fixed(buf, u.to_uint64(), 4)
      Ok(())
    }
    Ok(VI64(u)) => {
      write_fixed(buf, u, 8)
      Ok(())
    }
    Ok(_) => Err(InvalidWireType(offset=0, tag=0UL))
    Err(e) => Err(e)
  }
}

// ─────────────────────────────── 编码入口 ──────────────────────────────────

///|
/// 为单个字段产出 wire 字段记录并追加到 `entries`（含 repeated/packed/默认省略）。
fn typed_encode_field(
  schema : ProtoSchema,
  f : ProtoField,
  v : TypedValue,
  entries : Array[FieldEntry],
  force_packed : Bool,
) -> Result[Unit, DecodeError] {
  match f.label {
    LRepeated(packed~) =>
      match v {
        TList(elems) =>
          if proto_is_numeric_scalar(f.ptype) && (packed || force_packed) {
            let buf : Array[Byte] = []
            for e in elems {
              match write_scalar_to_buf(schema, f.ptype, e, buf) {
                Ok(_) => ()
                Err(er) => return Err(er)
              }
            }
            // proto3：空 packed 视为默认，省略不写。
            if buf.length() > 0 {
              entries.push(
                FieldEntry::new(
                  f.number,
                  FieldValue::VBytes(Bytes::from_array(buf)),
                ),
              )
            }
            Ok(())
          } else {
            for e in elems {
              match encode_scalar_value(schema, f.ptype, e) {
                Ok(fv) => entries.push(FieldEntry::new(f.number, fv))
                Err(er) => return Err(er)
              }
            }
            Ok(())
          }
        _ => Err(InvalidWireType(offset=0, tag=f.number.to_uint64()))
      }
    _ =>
      // singular / oneof 成员：取默认值的标量省略。
      if proto_is_scalar(f.ptype) && typed_is_default(v) {
        Ok(())
      } else {
        match encode_scalar_value(schema, f.ptype, v) {
          Ok(fv) => {
            entries.push(FieldEntry::new(f.number, fv))
            Ok(())
          }
          Err(er) => Err(er)
        }
      }
  }
}

///|
/// 为单个 map 字段产出键值对条目记录（每对编码为 `{1:key, 2:value}` 嵌套消息）。
fn typed_encode_map(
  schema : ProtoSchema,
  mp : MapEntry,
  v : TypedValue,
  entries : Array[FieldEntry],
) -> Result[Unit, DecodeError] {
  match v {
    TMap(pairs) => {
      for pair in pairs {
        let (k, val) = pair
        let sub : Array[FieldEntry] = []
        match encode_scalar_value(schema, mp.key, k) {
          Ok(fv) => sub.push(FieldEntry::new(1, fv))
          Err(e) => return Err(e)
        }
        match encode_scalar_value(schema, mp.value, val) {
          Ok(fv) => sub.push(FieldEntry::new(2, fv))
          Err(e) => return Err(e)
        }
        entries.push(
          FieldEntry::new(
            mp.number,
            FieldValue::VBytes(encode(Message::from_fields(sub))),
          ),
        )
      }
      Ok(())
    }
    _ => Err(InvalidWireType(offset=0, tag=mp.number.to_uint64()))
  }
}

///|
/// 构造一条消息的全部 wire 字段记录序列（字段定义顺序 + map + 未知字段）。
fn typed_build_entries(
  schema : ProtoSchema,
  msg_name : String,
  msg : TypedMessage,
  force_packed : Bool,
) -> Result[Array[FieldEntry], DecodeError] {
  let pmsg = match schema.message(msg_name) {
    Some(m) => m
    None => return Err(InvalidFieldNumber(offset=0, number=0))
  }
  let entries : Array[FieldEntry] = []
  for f in pmsg.fields {
    match msg.fields.get(f.number) {
      None => ()
      Some(v) =>
        match typed_encode_field(schema, f, v, entries, force_packed) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
    }
  }
  for mp in pmsg.maps {
    match msg.fields.get(mp.number) {
      None => ()
      Some(v) =>
        match typed_encode_map(schema, mp, v, entries) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
    }
  }
  for u in msg.unknown {
    entries.push(u)
  }
  Ok(entries)
}

///|
/// 模式驱动的类型化编码（R1.1–1.7）。取默认值的标量省略（R1.7）；未知字段写回（R2.2）。
pub fn encode_typed(
  schema : ProtoSchema,
  msg_name : String,
  msg : TypedMessage,
) -> Result[Bytes, DecodeError] {
  match typed_build_entries(schema, msg_name, msg, false) {
    Ok(entries) => Ok(encode(Message::from_fields(entries)))
    Err(e) => Err(e)
  }
}

// ─────────────────────────────── 解码入口 ──────────────────────────────────

///|
/// 将单个 wire 取值按声明 `ProtoType` 反向解释为类型化取值。
fn typed_interpret_scalar(
  schema : ProtoSchema,
  t : ProtoType,
  fv : FieldValue,
) -> Result[TypedValue, DecodeError] {
  match (t, fv) {
    (PInt32, VVarint(u)) =>
      Ok(TInt(u.to_uint().reinterpret_as_int().to_int64()))
    (PInt64, VVarint(u)) => Ok(TInt(u.reinterpret_as_int64()))
    (PUInt32, VVarint(u)) => Ok(TUInt(u & 0xFFFFFFFFUL))
    (PUInt64, VVarint(u)) => Ok(TUInt(u))
    (PSInt32, VVarint(u)) => Ok(TInt(zigzag_decode_32(u.to_uint()).to_int64()))
    (PSInt64, VVarint(u)) => Ok(TInt(zigzag_decode_64(u)))
    (PBool, VVarint(u)) => Ok(TBoolV(u != 0UL))
    (PEnum(_), VVarint(u)) => Ok(TEnumV(u.to_uint().reinterpret_as_int()))
    (PFixed32, VI32(u)) => Ok(TUInt(u.to_uint64()))
    (PSFixed32, VI32(u)) => Ok(TInt(u.reinterpret_as_int().to_int64()))
    (PFloat, VI32(u)) => Ok(TFloatV(bits_to_float(u)))
    (PFixed64, VI64(u)) => Ok(TUInt(u))
    (PSFixed64, VI64(u)) => Ok(TInt(u.reinterpret_as_int64()))
    (PDouble, VI64(u)) => Ok(TDoubleV(bits_to_double(u)))
    (PString, VBytes(b)) => Ok(TStringV(bytes_to_string(b)))
    (PBytes, VBytes(b)) => Ok(TBytesV(b))
    (PMessage(name), VBytes(b)) =>
      match decode_typed(schema, name, b) {
        Ok(inner) => Ok(TMsg(inner))
        Err(e) => Err(e)
      }
    _ => Err(InvalidWireType(offset=0, tag=0UL))
  }
}

///|
/// 将 packed 载荷拆为元素序列（仅数值标量）。
fn typed_unpack(
  t : ProtoType,
  payload : Bytes,
) -> Result[Array[TypedValue], DecodeError] {
  let elems : Array[TypedValue] = []
  let empty = ProtoSchema::empty()
  let wt = proto_wire_type(t)
  let mut pos = 0
  while pos < payload.length() {
    match wt {
      Varint => {
        let (u, next) = match read_varint(payload, pos) {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        pos = next
        match typed_interpret_scalar(empty, t, VVarint(u)) {
          Ok(tv) => elems.push(tv)
          Err(e) => return Err(e)
        }
      }
      I32 => {
        let (u, next) = match read_fixed(payload, pos, 4) {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        pos = next
        match typed_interpret_scalar(empty, t, VI32(u.to_uint())) {
          Ok(tv) => elems.push(tv)
          Err(e) => return Err(e)
        }
      }
      I64 => {
        let (u, next) = match read_fixed(payload, pos, 8) {
          Ok(p) => p
          Err(e) => return Err(e)
        }
        pos = next
        match typed_interpret_scalar(empty, t, VI64(u)) {
          Ok(tv) => elems.push(tv)
          Err(e) => return Err(e)
        }
      }
      Len => return Err(InvalidWireType(offset=0, tag=0UL))
    }
  }
  Ok(elems)
}

///|
/// 在 `fields` 的 `number` 处追加 repeated 元素（已存在则就地追加，否则新建 TList）。
fn typed_append_list(
  fields : Map[Int, TypedValue],
  number : Int,
  more : Array[TypedValue],
) -> Unit {
  match fields.get(number) {
    Some(TList(existing)) =>
      for x in more {
        existing.push(x)
      }
    _ => {
      let arr : Array[TypedValue] = []
      for x in more {
        arr.push(x)
      }
      fields[number] = TList(arr)
    }
  }
}

///|
/// 在 `fields` 的 `number` 处追加一对 map 键值（已存在则就地追加，否则新建 TMap）。
fn typed_append_map(
  fields : Map[Int, TypedValue],
  number : Int,
  k : TypedValue,
  v : TypedValue,
) -> Unit {
  match fields.get(number) {
    Some(TMap(existing)) => existing.push((k, v))
    _ => fields[number] = TMap([(k, v)])
  }
}

///|
/// 在消息字段定义中按字段号查找常规字段。
fn typed_lookup_field(pmsg : ProtoMessage, number : Int) -> ProtoField? {
  for f in pmsg.fields {
    if f.number == number {
      return Some(f)
    }
  }
  None
}

///|
/// 在消息字段定义中按字段号查找 map 字段。
fn typed_lookup_map(pmsg : ProtoMessage, number : Int) -> MapEntry? {
  for mp in pmsg.maps {
    if mp.number == number {
      return Some(mp)
    }
  }
  None
}

///|
/// 将一条 wire 字段记录按其字段定义解释并累加到 `fields`。
fn typed_decode_into(
  schema : ProtoSchema,
  f : ProtoField,
  entry : FieldEntry,
  fields : Map[Int, TypedValue],
) -> Result[Unit, DecodeError] {
  match f.label {
    LRepeated(..) =>
      if proto_is_numeric_scalar(f.ptype) {
        match entry.value {
          VBytes(payload) => {
            // packed：拆包全部元素。
            let elems = match typed_unpack(f.ptype, payload) {
              Ok(es) => es
              Err(e) => return Err(e)
            }
            typed_append_list(fields, f.number, elems)
            Ok(())
          }
          other =>
            // 非 packed：单元素。
            match typed_interpret_scalar(schema, f.ptype, other) {
              Ok(tv) => {
                typed_append_list(fields, f.number, [tv])
                Ok(())
              }
              Err(e) => Err(e)
            }
        }
      } else {
        // string/bytes/message repeated：单个 Len 元素。
        match typed_interpret_scalar(schema, f.ptype, entry.value) {
          Ok(tv) => {
            typed_append_list(fields, f.number, [tv])
            Ok(())
          }
          Err(e) => Err(e)
        }
      }
    _ =>
      // singular：last-wins。
      match typed_interpret_scalar(schema, f.ptype, entry.value) {
        Ok(tv) => {
          fields[f.number] = tv
          Ok(())
        }
        Err(e) => Err(e)
      }
  }
}

///|
/// 将一条 map 字段的条目记录解释为键值对并累加到 `fields`。
fn typed_decode_map_into(
  schema : ProtoSchema,
  mp : MapEntry,
  entry : FieldEntry,
  fields : Map[Int, TypedValue],
) -> Result[Unit, DecodeError] {
  match entry.value {
    VBytes(payload) => {
      let sub = match decode(payload, Schema::empty()) {
        Ok(m) => m
        Err(e) => return Err(e)
      }
      let mut key_fv : FieldValue? = None
      let mut val_fv : FieldValue? = None
      for fe in sub.fields {
        if fe.number == 1 {
          key_fv = Some(fe.value)
        } else if fe.number == 2 {
          val_fv = Some(fe.value)
        }
      }
      let k = match key_fv {
        Some(fv) =>
          match typed_interpret_scalar(schema, mp.key, fv) {
            Ok(tv) => tv
            Err(e) => return Err(e)
          }
        None => typed_default(mp.key)
      }
      let val = match val_fv {
        Some(fv) =>
          match typed_interpret_scalar(schema, mp.value, fv) {
            Ok(tv) => tv
            Err(e) => return Err(e)
          }
        None => typed_default(mp.value)
      }
      typed_append_map(fields, mp.number, k, val)
      Ok(())
    }
    _ => Err(InvalidWireType(offset=0, tag=mp.number.to_uint64()))
  }
}

///|
/// 模式驱动的类型化解码（R1.1–1.6, 1.8；未知字段保留 R2.1）。
///
/// 先以既有 `decode` 做 wire 粒度扫描（非法字节错误含偏移由其透传，R11.3），
/// 再按 schema 把字段号映射为命名字段并按声明类型反向解释；schema 中无定义的
/// 字段进入 `unknown` 原样保留。失败时返回 `Err` 而非部分构造消息。
pub fn decode_typed(
  schema : ProtoSchema,
  msg_name : String,
  bytes : Bytes,
) -> Result[TypedMessage, DecodeError] {
  let pmsg = match schema.message(msg_name) {
    Some(m) => m
    None => return Err(InvalidFieldNumber(offset=0, number=0))
  }
  let wire = match decode(bytes, Schema::empty()) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  let fields : Map[Int, TypedValue] = {}
  let unknown : Array[FieldEntry] = []
  for entry in wire.fields {
    match typed_lookup_field(pmsg, entry.number) {
      Some(f) =>
        match typed_decode_into(schema, f, entry, fields) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      None =>
        match typed_lookup_map(pmsg, entry.number) {
          Some(mp) =>
            match typed_decode_map_into(schema, mp, entry, fields) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
          None => unknown.push(entry)
        }
    }
  }
  Ok({ fields, unknown })
}
