// codec_test.mbt —— ByteWriter/ByteReader 黑盒测试：边界值定向 +
// round-trip 逐值一致 PBT + 畸形输入安全（None 不 panic）。

///|
test "varint boundary values round-trip with expected sizes" {
  // (值, 期望编码字节数)：LEB128 每 7 位一字节。
  let cases : Array[(UInt64, Int)] = [
    (0UL, 1),
    (1UL, 1),
    (127UL, 1),
    (128UL, 2),
    (16383UL, 2),
    (16384UL, 3),
    (0xFFFF_FFFFUL, 5),
    (0xFFFF_FFFF_FFFF_FFFFUL, 10),
  ]
  for c in cases {
    let w = @infra_codec.ByteWriter::new()
    w.write_varint(c.0)
    assert_eq(w.length(), c.1)
    let r = @infra_codec.ByteReader::new(w.to_bytes())
    assert_true(r.read_varint() == Some(c.0))
    assert_eq(r.remaining(), 0)
  }
}

///|
test "zigzag folds small negatives into short encodings" {
  // 小绝对值负数编码短（protobuf sint64 语义）。
  let cases : Array[(Int64, Int)] = [
    (0L, 1),
    (-1L, 1),
    (1L, 1),
    (-64L, 1),
    (64L, 2),
    (-9223372036854775808L, 10),
    (9223372036854775807L, 10),
  ]
  for c in cases {
    let w = @infra_codec.ByteWriter::new()
    w.write_zigzag(c.0)
    assert_eq(w.length(), c.1)
    let r = @infra_codec.ByteReader::new(w.to_bytes())
    assert_true(r.read_zigzag() == Some(c.0))
  }
}

///|
test "fixed u32/u64 little-endian + bytes + string round-trip" {
  let w = @infra_codec.ByteWriter::new()
  w.write_u32(0xDEAD_BEEF)
  w.write_u64(0x0102_0304_0506_0708UL)
  w.write_bytes([1, 2, 250, 255])
  w.write_string("路径规划 pathfinding ✓")
  let bytes = w.to_bytes()
  // fixed32 小端首字节为最低位。
  assert_eq(bytes[0], 0xEF)
  assert_eq(bytes[3], 0xDE)
  let r = @infra_codec.ByteReader::new(bytes)
  assert_true(r.read_u32() == Some(0xDEAD_BEEF))
  assert_true(r.read_u64() == Some(0x0102_0304_0506_0708UL))
  assert_true(r.read_bytes() == Some([1, 2, 250, 255]))
  assert_true(r.read_string() == Some("路径规划 pathfinding ✓"))
  assert_eq(r.remaining(), 0)
}

///|
test "malformed input returns None without panicking" {
  // 截断 varint（续传位悬空）。
  let r1 = @infra_codec.ByteReader::new([0x80, 0x80])
  assert_true(r1.read_varint() == None)
  // 超长 varint（11 字节全续传）。
  let r2 = @infra_codec.ByteReader::new([
    0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
  ])
  assert_true(r2.read_varint() == None)
  // bytes 长度前缀超过剩余。
  let r3 = @infra_codec.ByteReader::new([10, 1, 2])
  assert_true(r3.read_bytes() == None)
  // 定长读取越界。
  let r4 = @infra_codec.ByteReader::new([1, 2, 3])
  assert_true(r4.read_u32() == None)
  assert_true(r4.read_u64() == None)
}

///|
test "E2 property: mixed-field stream round-trips exactly (200 iters)" {
  let rng = @infra_pbt.rng_new(20260714)
  for _iter in 0..<200 {
    let w = @infra_codec.ByteWriter::new()
    let kinds : Array[Int] = []
    let vints : Array[UInt64] = []
    let zints : Array[Int64] = []
    let fixed : Array[UInt64] = []
    let blobs : Array[Array[Int]] = []
    let n = 5 + rng.next_below(40)
    for _ in 0..<n {
      let kind = rng.next_below(4)
      kinds.push(kind)
      match kind {
        0 => {
          // 随机跨度 varint：拼两段 32 位随机构造 64 位。
          let v = rng.next()
          let v = v >> rng.next_below(64)
          vints.push(v)
          w.write_varint(v)
        }
        1 => {
          let raw = rng.next()
          let v = (raw >> rng.next_below(64)).reinterpret_as_int64()
          let v = if rng.next_below(2) == 1 { -v } else { v }
          zints.push(v)
          w.write_zigzag(v)
        }
        2 => {
          let v = rng.next()
          fixed.push(v)
          w.write_u64(v)
        }
        _ => {
          let blob : Array[Int] = []
          for _ in 0..<rng.next_below(20) {
            blob.push(rng.next_below(256))
          }
          blobs.push(blob)
          w.write_bytes(blob)
        }
      }
    }
    let r = @infra_codec.ByteReader::new(w.to_bytes())
    let mut vi = 0
    let mut zi = 0
    let mut fi = 0
    let mut bi = 0
    for kind in kinds {
      match kind {
        0 => {
          assert_true(r.read_varint() == Some(vints[vi]))
          vi = vi + 1
        }
        1 => {
          assert_true(r.read_zigzag() == Some(zints[zi]))
          zi = zi + 1
        }
        2 => {
          assert_true(r.read_u64() == Some(fixed[fi]))
          fi = fi + 1
        }
        _ => {
          assert_true(r.read_bytes() == Some(blobs[bi]))
          bi = bi + 1
        }
      }
    }
    // 流精确耗尽：编码器写出的每个字节都被解码器消费。
    assert_eq(r.remaining(), 0)
  }
}
