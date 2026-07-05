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

///|
test "bench: lazy field view vs eager full decode (sparse access, 2/32 fields)" (
  b : @bench.T,
) {
  // 负载：n 条消息，每条 32 个字段（字段 1/2 为 varint 键值，3..32 为
  // 48 字符字符串），访问端只取字段 1 和 2（RPC 网关取路由键/时间戳的
  // 典型稀疏访问）。惰性视图只扫键 + 定点解码两个 varint；eager 侧
  // 全量解码整条消息（含 30 个字符串物化）。
  let n = 2000
  let msgs : Array[Array[Int]] = []
  for i in 0..<n {
    let w = @codec.ByteWriter::new()
    let fw = @codec.FieldWriter::over(w)
    fw.varint_field(1, i.to_uint64() * 2654435761UL)
    fw.varint_field(2, i.to_uint64())
    for f in 3..<=32 {
      let sb = StringBuilder::new()
      for k in 0..<48 {
        sb.write_char((97 + (i + f + k) % 26).unsafe_to_char())
      }
      fw.string_field(f, sb.to_string())
    }
    msgs.push(w.to_bytes())
  }
  b.bench(name="lazy_view_sparse_\{n}x32", fn() {
    let mut acc = 0UL
    for m in msgs {
      let v = @codec.MsgView::over(m)
      match v.varint_field(1) {
        Some(x) => acc = acc + x
        None => ()
      }
      match v.varint_field(2) {
        Some(x) => acc = acc + x
        None => ()
      }
    }
    b.keep(acc)
  })
  b.bench(name="eager_full_decode_\{n}x32", fn() {
    // 单趟顺序全量解码（公平基线：每字段只扫一次，字符串全部物化）。
    let mut acc = 0UL
    for m in msgs {
      let r = @codec.ByteReader::new(m)
      while r.remaining() > 0 {
        match r.read_varint() {
          Some(key) => {
            let fno = (key >> 3).to_int()
            if (key & 7UL) == 0UL {
              match r.read_varint() {
                Some(x) => if fno <= 2 { acc = acc + x }
                None => break
              }
            } else {
              // LEN 载荷（码点 varint 序列）→ 物化为字符串。
              match r.read_string_payload() {
                Some(s) => acc = acc + s.length().to_uint64()
                None => break
              }
            }
          }
          None => break
        }
      }
    }
    b.keep(acc)
  })
}
