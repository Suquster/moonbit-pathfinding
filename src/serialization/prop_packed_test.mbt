// prop_packed_test.mbt —— Property 6：packed 与非 packed 等价（任务 5.4）。
//
// Feature: serialization, Property 6: packed 与非 packed 等价（packed equivalence）
//
// 对任意由生成器产出的数值标量序列，将其编码为 packed 形式与编码为同字段号多次
// 出现的非 packed 形式，两者经解码得到相同的元素序列。
//
// 实现：构造仅差 `packed` 标志的两份 schema，对同一 `TList` 分别编码（packed /
// 非 packed），再以 packed schema 解码二者（解码同时支持两种 wire 形态），断言
// 元素序列一致。
//
// **Validates: Requirements 2.5, 2.8**

///|
/// 构造仅含一个 repeated 数值字段 `xs`（号 1）的单消息富模式。
fn pp_schema(t : ProtoType, packed : Bool) -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields: [
          {
            name: "xs",
            number: 1,
            ptype: t,
            label: LRepeated(packed~),
            options: [],
          },
        ],
        maps: [],
        oneofs: [],
        reserved_numbers: [],
        reserved_names: [],
        nested_messages: [],
        nested_enums: [],
      },
    ],
    enums: [],
  }
}

///|
/// （数值类型, 元素序列）生成器（≥1 元素，避免空 repeated 被默认省略）。
fn pp_gen() -> @infra_pbt.Gen[(ProtoType, Array[TypedValue])] {
  @infra_pbt.Gen::new(fn(rng) {
    let numerics = sg_numeric_types()
    let t = numerics[rng.next_below(numerics.length())]
    let n = rng.next_range(1, 5)
    let elems : Array[TypedValue] = []
    for _i in 0..<n {
      elems.push(sg_value_for(rng, t))
    }
    (t, elems)
  })
}

///|
/// 校验某（数值类型, 元素序列）的 packed / 非 packed 解码等价。
fn pp_check(t : ProtoType, elems : Array[TypedValue]) -> Bool {
  let schema_packed = pp_schema(t, true)
  let schema_nonpacked = pp_schema(t, false)
  let m = TypedMessage::new().set(1, TList(elems))
  let packed_bytes = match encode_typed(schema_packed, "M", m) {
    Ok(b) => b
    Err(_) => return false
  }
  let nonpacked_bytes = match encode_typed(schema_nonpacked, "M", m) {
    Ok(b) => b
    Err(_) => return false
  }
  let a = match decode_typed(schema_packed, "M", packed_bytes) {
    Ok(x) => x
    Err(_) => return false
  }
  let b = match decode_typed(schema_packed, "M", nonpacked_bytes) {
    Ok(x) => x
    Err(_) => return false
  }
  a == b && a.get(1) == Some(TList(elems))
}

///|
/// Feature: serialization, Property 6: packed 与非 packed 等价（packed equivalence）
///
/// **Validates: Requirements 2.5, 2.8**
test "Feature: serialization, Property 6: packed equivalence" {
  let ok = @infra_pbt.holds_for_all(pp_gen(), fn(pair) {
    let (t, elems) = pair
    pp_check(t, elems)
  })
  assert_true(ok)
}
