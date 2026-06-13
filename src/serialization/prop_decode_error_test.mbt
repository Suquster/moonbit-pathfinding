// prop_decode_error_test.mbt —— Property 10：解码错误位置与无部分产物（任务 5.5）。
//
// Feature: serialization, Property 10: 解码错误位置与无部分产物（decode-error offset）
//
// 对任意由生成器产出的非法字节序列，`decode` 与 `decode_typed` 均返回携带出错字节
// 偏移（∈ `[0, 输入长度]`）的 `DecodeError`，且为 `Err` 而非 `Ok(部分消息)`。
//
// **Validates: Requirements 11.3**

///|
/// 生成一个值落在 `[lo, hi]`（闭区间）的字节。
fn de_byte_in(rng : @infra_pbt.Rng, lo : Int, hi : Int) -> Byte {
  rng.next_range(lo, hi).to_byte()
}

///|
/// 「wire format 非法字节序列」生成器（与 wire.mbt 各错误路径精确对齐）。
fn de_gen_illegal() -> @infra_pbt.Gen[Bytes] {
  @infra_pbt.Gen::new(fn(rng) {
    match rng.next_below(6) {
      // 0. 截断 / 过长 varint tag。
      0 => {
        let n = rng.next_range(1, 11)
        let buf : Array[Byte] = []
        for _i in 0..<n {
          buf.push(de_byte_in(rng, 0x80, 0xFF))
        }
        Bytes::from_array(buf)
      }
      // 1. 非法 wire 类型（低三位 ∈ {3,4,6,7}）。
      1 => {
        let number = rng.next_range(1, 15)
        let wts = [3, 4, 6, 7]
        let wt = wts[rng.next_below(wts.length())]
        Bytes::from_array([(number * 8 + wt).to_byte()])
      }
      // 2. 非法字段号 0。
      2 => Bytes::from_array([rng.next_below(8).to_byte()])
      // 3. 定长字段字节不足。
      3 => {
        let number = rng.next_range(1, 15)
        let is64 = rng.next_bool()
        let wt = if is64 { 1 } else { 5 }
        let needed = if is64 { 8 } else { 4 }
        let buf : Array[Byte] = [(number * 8 + wt).to_byte()]
        let avail = rng.next_below(needed)
        for _i in 0..<avail {
          buf.push(de_byte_in(rng, 0x00, 0xFF))
        }
        Bytes::from_array(buf)
      }
      // 4. Len 长度前缀越界。
      4 => {
        let number = rng.next_range(1, 15)
        let buf : Array[Byte] = [(number * 8 + 2).to_byte()]
        let declared = rng.next_range(2, 127)
        buf.push(declared.to_byte())
        let content = rng.next_below(declared)
        for _i in 0..<content {
          buf.push(de_byte_in(rng, 0x00, 0xFF))
        }
        Bytes::from_array(buf)
      }
      // 5. Len 长度前缀自身截断。
      _ => {
        let number = rng.next_range(1, 15)
        let buf : Array[Byte] = [(number * 8 + 2).to_byte()]
        let n = rng.next_range(1, 11)
        for _i in 0..<n {
          buf.push(de_byte_in(rng, 0x80, 0xFF))
        }
        Bytes::from_array(buf)
      }
    }
  })
}

///|
/// 用于 `decode_typed` 的最小富模式（字段 1 = int32）。
fn de_schema() -> ProtoSchema {
  {
    messages: [
      {
        name: "M",
        fields: [
          { name: "x", number: 1, ptype: PInt32, label: LSingular, options: [] },
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
/// 校验非法字节使 `decode` 与 `decode_typed` 均报含合法偏移的错误（无部分产物）。
fn de_check(bytes : Bytes) -> Bool {
  let r1 = match decode(bytes, Schema::empty()) {
    Ok(_) => false
    Err(e) => {
      let o = e.offset()
      o >= 0 && o <= bytes.length()
    }
  }
  let r2 = match decode_typed(de_schema(), "M", bytes) {
    Ok(_) => false
    Err(e) => {
      let o = e.offset()
      o >= 0 && o <= bytes.length()
    }
  }
  r1 && r2
}

///|
/// Feature: serialization, Property 10: 解码错误位置与无部分产物
///
/// **Validates: Requirements 11.3**
test "Feature: serialization, Property 10: decode-error offset (decode and decode_typed)" {
  let ok = @infra_pbt.holds_for_all(de_gen_illegal(), fn(bytes) { de_check(bytes) })
  assert_true(ok)
}

///|
/// 健全性：生成器产出的样本确实全部非法（对 `decode` 而言）。
test "Feature: serialization, Property 10: generator only emits illegal byte sequences" {
  let all_illegal = @infra_pbt.holds_for_all(de_gen_illegal(), fn(bytes) {
    match decode(bytes, Schema::empty()) {
      Err(_) => true
      Ok(_) => false
    }
  })
  assert_true(all_illegal)
}
