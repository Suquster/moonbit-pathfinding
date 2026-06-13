// prop_error_test.mbt —— Serialization_Framework 任务 7.4 的错误条件属性测试。
//
// Feature: moonbit-infra-suite, Property 21: Protobuf 非法字节错误条件
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 21，复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all`
// 模板（每条属性 ≥100 次迭代，由 `holds_for_all` 默认 `iters=100` 保证）。
//
// 性质（design.md Property 21）：
//   *对任意* 不符合 protobuf wire format 的字节序列，`decode` 应返回包含出错
//   字节偏移的 `DecodeError`，且**不产生部分构造的对象**。
//
// **Validates: Requirements 9.4**
//
// 设计要点：
//   * `gen_illegal_bytes` —— 按确定性随机源在 6 个互斥的「wire format 非法
//     类别」间选择，每个类别都构造出对 wire.mbt 的 `decode` 而言**保证非法**
//     的字节序列（与各错误路径精确对齐）：
//       0. 截断 / 过长 varint tag    （续位标志恒置位且到末尾）→ UnexpectedEof / MalformedVarint
//       1. 非法 wire 类型            （tag 低三位 ∈ {3,4,6,7}）  → InvalidWireType
//       2. 非法字段号 0              （tag 高位为 0）            → InvalidFieldNumber
//       3. 定长字段字节不足          （I32 不足 4 / I64 不足 8） → UnexpectedEof
//       4. Len 长度前缀越界          （声明长度 > 剩余字节）    → UnexpectedEof
//       5. Len 长度前缀自身截断      （长度 varint 续位到末尾）  → UnexpectedEof / MalformedVarint
//   * 「不产生部分构造对象」由 `decode` 的返回契约直接保证：失败时返回
//     `Err(DecodeError)`，根本不存在任何 `Message`（连部分构造的都没有）；
//     故属性以「结果必为 Err」断言之，并校验偏移落在合法区间 `[0, 长度]`。

// ---------------------------------------------------------------------------
// 非法字节序列生成器（generator）—— 复用 @infra_pbt 种子驱动随机源
// ---------------------------------------------------------------------------

///|
/// 生成一个值落在 `[lo, hi]`（闭区间）的字节。
fn gen_byte_in(rng : @infra_pbt.Rng, lo : Int, hi : Int) -> Byte {
  rng.next_range(lo, hi).to_byte()
}

///|
/// 确定性「wire format 非法字节序列」生成器。
///
/// 在 6 个互斥的非法类别间按随机源选择，每个类别都构造出对 `decode` 而言
/// **保证非法**的字节序列。返回的每个样本都应使 `decode` 返回 `Err`。
///
/// 注：所有类别均把字段号约束在 `1..=15`，使 tag 落在单字节 varint 区间内，
/// 从而让「非法性」完全由所选类别的骨架决定，不会被意外「修复」。
fn gen_illegal_bytes() -> @infra_pbt.Gen[Bytes] {
  @infra_pbt.Gen::new(fn(rng) {
    match rng.next_below(6) {
      // 0. 截断 / 过长 varint tag：1..11 个字节全部置续位标志（0x80..0xFF），
      //    永不终止 → read_varint 以 UnexpectedEof 或 MalformedVarint 失败。
      0 => {
        let n = rng.next_range(1, 11)
        let buf : Array[Byte] = []
        for _i in 0..<n {
          buf.push(gen_byte_in(rng, 0x80, 0xFF))
        }
        Bytes::from_array(buf)
      }
      // 1. 非法 wire 类型：单字节 tag，字段号 1..15、wire 低三位 ∈ {3,4,6,7}。
      1 => {
        let number = rng.next_range(1, 15)
        let wts = [3, 4, 6, 7]
        let wt = wts[rng.next_below(wts.length())]
        // (number<<3)|wt ≤ (15<<3)|7 = 127 → 单字节、高位清零，read_varint 终止。
        Bytes::from_array([(number * 8 + wt).to_byte()])
      }
      // 2. 非法字段号 0：单字节 tag 落在 0..7（高位字段号为 0）。
      2 => Bytes::from_array([rng.next_below(8).to_byte()])
      // 3. 定长字段字节不足：合法 tag（I32/I64）后给出严格少于所需的数据字节。
      3 => {
        let number = rng.next_range(1, 15)
        let is64 = rng.next_bool()
        let wt = if is64 { 1 } else { 5 }
        let needed = if is64 { 8 } else { 4 }
        let buf : Array[Byte] = [(number * 8 + wt).to_byte()]
        let avail = rng.next_below(needed) // 0..needed-1，严格不足。
        for _i in 0..<avail {
          buf.push(gen_byte_in(rng, 0x00, 0xFF))
        }
        Bytes::from_array(buf)
      }
      // 4. Len 长度前缀越界：声明长度严格大于其后剩余的内容字节数。
      4 => {
        let number = rng.next_range(1, 15)
        let buf : Array[Byte] = [(number * 8 + 2).to_byte()] // wire Len(2)
        let declared = rng.next_range(2, 127) // 单字节 varint（< 128）。
        buf.push(declared.to_byte())
        let content = rng.next_below(declared) // 0..declared-1 < declared。
        for _i in 0..<content {
          buf.push(gen_byte_in(rng, 0x00, 0xFF))
        }
        Bytes::from_array(buf)
      }
      // 5. Len 长度前缀自身截断：合法 tag 后，长度 varint 续位到末尾不终止。
      _ => {
        let number = rng.next_range(1, 15)
        let buf : Array[Byte] = [(number * 8 + 2).to_byte()] // wire Len(2)
        let n = rng.next_range(1, 11)
        for _i in 0..<n {
          buf.push(gen_byte_in(rng, 0x80, 0xFF))
        }
        Bytes::from_array(buf)
      }
    }
  })
}

// ---------------------------------------------------------------------------
// Property 21：非法字节错误条件（≥100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 21: Protobuf 非法字节错误条件
///
/// 对任意不符合 wire format 的字节序列，`decode` 应：
///   1. 返回 `Err`（解码错误），而非 `Ok`——即**不产生任何（含部分构造的）
///      `Message` 对象**；
///   2. 错误携带落在 `[0, 字节长度]` 内的出错字节偏移（含定位信息）。
///
/// **Validates: Requirements 9.4**
test "Feature: moonbit-infra-suite, Property 21: illegal bytes yield located error and no partial object" {
  let ok = @infra_pbt.holds_for_all(gen_illegal_bytes(), fn(bytes) {
    match decode(bytes, Schema::empty()) {
      // 本应非法却解码成功 → 性质被违反（产生了不该存在的对象）。
      Ok(_) => false
      Err(e) => {
        // 出错偏移必须含定位且落在合法区间 [0, 长度] 内。
        let off = e.offset()
        off >= 0 && off <= bytes.length()
      }
    }
  })
  assert_true(ok)
}

///|
/// 健全性（sanity）：生成器产出的样本确实全部非法。
///
/// 单独以 100 次迭代校验「每个生成样本都使 decode 返回 Err」，确保上方主
/// 属性不会因生成器漏产合法字节序列而被「平凡满足」（vacuously true）。
///
/// **Validates: Requirements 9.4**
test "Feature: moonbit-infra-suite, Property 21: generator only emits illegal byte sequences" {
  let all_illegal = @infra_pbt.holds_for_all(gen_illegal_bytes(), fn(bytes) {
    match decode(bytes, Schema::empty()) {
      Err(_) => true
      Ok(_) => false
    }
  })
  assert_true(all_illegal)
}
