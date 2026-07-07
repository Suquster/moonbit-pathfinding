// schema_evolution.mbt —— schema 演进 / 版本兼容性检查器（C3 旗舰深化）。
//
// 对标 protobuf 官方「Updating A Message Type」规则与 Buf breaking-change
// 检查器的 WIRE 级语义：给定同一消息的旧版（reader 侧）与新版（writer 侧）
// 定义，静态判定新版是否**线上兼容**（旧读者可安全解码新写者的字节流）。
//
// 检查规则（proto3 wire 兼容语义）：
//   * 同号字段类型变化 → 仅同 wire 形态且解释一致的组视为兼容
//     （int32/int64/uint32/uint64/bool 互通；sint32/sint64 互通；
//      fixed32/sfixed32 互通；fixed64/sfixed64 互通；string/bytes 互通）；
//   * 删除字段：必须把字段号登记进 `reserved`（防止未来复用串义）；
//   * 复用 reserved 字段号 / 名称 → 破坏性；
//   * singular ↔ repeated 切换（数值标量 packed 形态变化）→ 破坏性；
//   * oneof 成员移出 / 移入既有 oneof → 破坏性（成员归属变化改变互斥语义）；
//   * 新增字段（新字段号）→ 兼容（旧读者按未知字段跳过并可保留重编码）。
//
// 输出 `Array[BreakingChange]`：空数组即兼容；每项含字段号与人类可读根因，
// 供 CI 门禁与错误报告使用。纯函数、无 panic、三后端一致。

///|
/// 一处破坏性变更：字段号（0 表示消息级问题）+ 根因描述。
pub(all) struct BreakingChange {
  field_number : Int
  reason : String
} derive(Eq, Debug)

///|
/// wire 兼容组：同组内的类型互换不破坏旧读者解码。
fn wire_group(t : ProtoType) -> Int {
  match t {
    PInt32 | PInt64 | PUInt32 | PUInt64 | PBool => 1 // 普通 varint 互通
    PSInt32 | PSInt64 => 2 // zigzag varint
    PFixed32 | PSFixed32 => 3 // I32 定长整数
    PFixed64 | PSFixed64 => 4 // I64 定长整数
    PFloat => 5
    PDouble => 6
    PString | PBytes => 7 // Len 字节互通
    PEnum(_) => 1 // 枚举 wire 上即 varint（与 int32 互通）
    PMessage(name) => {
      // 消息类型仅与同名消息兼容（嵌套结构自身另行递归检查）。
      let mut h = 100
      for c in name {
        h = h * 31 + c.to_int()
      }
      h
    }
  }
}

///|
/// 字段号是否落入 reserved 区间或名称是否被 reserved。
fn is_reserved(msg : ProtoMessage, number : Int, name : String) -> Bool {
  for r in msg.reserved_numbers {
    if number >= r.lo && number <= r.hi {
      return true
    }
  }
  for n in msg.reserved_names {
    if n == name {
      return true
    }
  }
  false
}

///|
/// 查字段所属 oneof 组名（不属于任何 oneof 返回 None）。
fn oneof_group_of(field : ProtoField) -> String? {
  match field.label {
    LOneof(group~) => Some(group)
    _ => None
  }
}

///|
/// 判定同一消息 old（reader）→ new（writer）的 wire 级演进兼容性。
/// 返回全部破坏性变更（空数组 = 兼容）。
pub fn check_message_evolution(
  old_msg : ProtoMessage,
  new_msg : ProtoMessage,
) -> Array[BreakingChange] {
  let breaks : Array[BreakingChange] = []
  // 1. 旧字段逐个核对。
  for of in old_msg.fields {
    let mut found = false
    for nf in new_msg.fields {
      if nf.number == of.number {
        found = true
        // 同号类型变化：wire 组必须一致。
        if wire_group(nf.ptype) != wire_group(of.ptype) {
          breaks.push({
            field_number: of.number,
            reason: "field \{of.name}: wire-incompatible type change",
          })
        }
        // singular ↔ repeated 切换。
        let old_rep = of.label is LRepeated(..)
        let new_rep = nf.label is LRepeated(..)
        if old_rep != new_rep {
          breaks.push({
            field_number: of.number,
            reason: "field \{of.name}: singular/repeated label change",
          })
        }
        // oneof 归属变化。
        if oneof_group_of(of) != oneof_group_of(nf) {
          breaks.push({
            field_number: of.number,
            reason: "field \{of.name}: oneof membership change",
          })
        }
        break
      }
    }
    if !found {
      // 删除字段必须 reserve 其号与名。
      if !is_reserved(new_msg, of.number, of.name) {
        breaks.push({
          field_number: of.number,
          reason: "field \{of.name}: removed without reserving number/name",
        })
      }
    }
  }
  // 2. 新字段不得复用旧版 reserved 的号 / 名。
  for nf in new_msg.fields {
    if is_reserved(old_msg, nf.number, nf.name) {
      breaks.push({
        field_number: nf.number,
        reason: "field \{nf.name}: reuses a reserved number or name",
      })
    }
  }
  breaks
}

///|
/// 整个 schema 的演进检查：逐消息（按限定名对齐）汇总破坏性变更；
/// 新版删除整个消息也视为破坏（旧读者引用悬空）。
pub fn check_schema_evolution(
  old_schema : ProtoSchema,
  new_schema : ProtoSchema,
) -> Array[BreakingChange] {
  let breaks : Array[BreakingChange] = []
  for om in old_schema.messages {
    match new_schema.message(om.name) {
      Some(nm) =>
        for b in check_message_evolution(om, nm) {
          breaks.push(b)
        }
      None =>
        breaks.push({
          field_number: 0,
          reason: "message \{om.name}: removed from schema",
        })
    }
  }
  breaks
}
