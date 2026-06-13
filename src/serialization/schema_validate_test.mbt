// schema_validate_test.mbt —— 模式校验单元测试（任务 3.5）。
//
// 覆盖重复字段号 / 命中 reserved / 未解析引用 / 枚举首值非 0 / 字段号越界各错误
// 场景与正向通过（R4.2–4.6）。

///|
/// 构造仅含给定字段的单消息富模式（可选附带 reserved）。
fn sv_schema(
  fields : Array[ProtoField],
  reserved_numbers : Array[ReservedRange],
  enums : Array[EnumDef],
) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields,
        maps: [],
        oneofs: [],
        reserved_numbers,
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums,
  }
}

///|
/// 单个字段构造辅助。
fn sv_field(name : String, number : Int, t : ProtoType) -> ProtoField {
  { name, number, ptype: t, label: LSingular, options: [] }
}

///|
/// 错误数组是否含某类诊断。
fn sv_has_duplicate(errs : Array[SchemaError]) -> Bool {
  for e in errs {
    if e is DuplicateFieldNumber(..) {
      return true
    }
  }
  false
}

///|
test "validate_schema rejects duplicate field numbers" {
  let s = sv_schema([sv_field("a", 1, PInt32), sv_field("b", 1, PString)], [], [])
  match validate_schema(s) {
    Ok(_) => fail("重复字段号应被拒绝")
    Err(errs) => assert_true(sv_has_duplicate(errs))
  }
}

///|
test "validate_schema rejects field hitting reserved number" {
  let s = sv_schema([sv_field("a", 5, PInt32)], [{ lo: 5, hi: 5 }], [])
  match validate_schema(s) {
    Ok(_) => fail("命中 reserved 的字段号应被拒绝")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e is ReservedConflict(..) {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
test "validate_schema rejects unresolved type reference" {
  let s = sv_schema([sv_field("c", 1, PMessage("Nope"))], [], [])
  match validate_schema(s) {
    Ok(_) => fail("未解析引用应被拒绝")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e is UnresolvedTypeRef(..) {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
test "validate_schema rejects enum whose first value is non-zero" {
  let s = sv_schema([sv_field("a", 1, PInt32)], [], [
    { name: "E", values: [("FIRST", 1), ("SECOND", 2)] },
  ])
  match validate_schema(s) {
    Ok(_) => fail("枚举首值非 0 应被拒绝")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e is EnumFirstValueNonZero(..) {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
test "validate_schema rejects out-of-range field number" {
  // 19000 落在 protobuf 实现保留区间 [19000, 19999]。
  let s = sv_schema([sv_field("a", 19000, PInt32)], [], [])
  match validate_schema(s) {
    Ok(_) => fail("保留区间字段号应被拒绝")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e is FieldNumberOutOfRange(..) {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
test "validate_schema accepts a well-formed schema" {
  let s = sv_schema(
    [sv_field("a", 1, PInt32), sv_field("b", 2, PString)],
    [{ lo: 100, hi: 100 }],
    [{ name: "E", values: [("E0", 0), ("E1", 1)] }],
  )
  match validate_schema(s) {
    Ok(_) => assert_true(true)
    Err(errs) => fail("合法模式不应报错：\{errs}")
  }
}
