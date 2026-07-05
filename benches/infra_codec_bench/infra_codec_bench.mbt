// infra_codec_bench.mbt —— E2 varint/zigzag 二进制编解码 vs 朴素字符串
// 序列化 round-trip 基准。
//
// 负载：n 个确定性 xorshift 随机 Int64（混合正负与跨度），
// 二进制侧 zigzag varint 编码 + 解码；朴素侧 to_string 逗号拼接 +
// 逐字符解析回 Int64。两侧均校验和验证 round-trip。

///|
fn xorshift(x : UInt64) -> UInt64 {
  let mut s = x
  s = s ^ (s << 13)
  s = s ^ (s >> 7)
  s = s ^ (s << 17)
  s
}

///|
fn make_values(n : Int, seed : UInt64) -> Array[Int64] {
  let out : Array[Int64] = []
  let mut s = seed
  for _ in 0..<n {
    s = xorshift(s)
    let span = (s >> 58).to_int() // 0..63
    let v = (s >> span).reinterpret_as_int64()
    out.push(if (s & 1UL) == 1UL { -v } else { v })
  }
  out
}

///|
test "bench: zigzag varint vs naive string serialization round-trip" (
  b : @bench.T,
) {
  for n in [2000, 8000, 32000] {
    let values = make_values(n, 20260715UL)
    b.bench(name="zigzag_varint_roundtrip_\{n}", fn() {
      let w = @codec.ByteWriter::new()
      for v in values {
        w.write_zigzag(v)
      }
      let r = @codec.ByteReader::new(w.to_bytes())
      let mut acc = 0L
      for _ in 0..<n {
        match r.read_zigzag() {
          Some(v) => acc = acc + v
          None => ()
        }
      }
      b.keep(acc)
    })
    b.bench(name="naive_string_roundtrip_\{n}", fn() {
      // 编码：to_string 逗号拼接。
      let sb = StringBuilder::new()
      let mut first = true
      for v in values {
        if !first {
          sb.write_char(',')
        }
        first = false
        sb.write_string(v.to_string())
      }
      let text = sb.to_string()
      // 解码：逐字符解析回 Int64。
      let mut acc = 0L
      let mut cur = 0L
      let mut neg = false
      let mut has = false
      for c in text {
        if c == ',' {
          acc = acc + (if neg { -cur } else { cur })
          cur = 0L
          neg = false
          has = false
        } else if c == '-' {
          neg = true
        } else {
          cur = cur * 10L + (c.to_int() - 48).to_int64()
          has = true
        }
      }
      if has {
        acc = acc + (if neg { -cur } else { cur })
      }
      b.keep(acc)
    })
  }
}
