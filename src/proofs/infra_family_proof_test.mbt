// infra_family_proof_test.mbt —— INFRA 家族证明谓词的运行时见证（G-B4）。
//
// 以真实包实现（@infra_compress / @infra_hash / @regex_engine）驱动
// infra_family_proof.mbt 的谓词，每条属性 ≥100 迭代（holds_for_all 默认）。
// 跨包依赖仅存在于测试期，proofs 生产代码保持最小依赖。

///|
/// 随机字节负载生成器（长度 ≤ 200，混合窄字母表与全字节域）。
fn gen_bytes() -> @infra_pbt.Gen[Array[Int]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_below(200)
    let out : Array[Int] = []
    for _k in 0..<n {
      if rng.next_bool() {
        out.push(97 + rng.next_below(4))
      } else {
        out.push(rng.next_below(256))
      }
    }
    out
  })
}

///|
test "谓词 · zstd 往返恒等 + 魔数前缀封闭（PBT）" {
  let ok = @infra_pbt.holds_for_all(gen_bytes(), fn(data) {
    let frame = @infra_compress.zstd_compress(data, true)
    if !has_magic_prefix(frame, [0x28, 0xB5, 0x2F, 0xFD]) {
      return false
    }
    match @infra_compress.zstd_decompress(frame, 1 << 20) {
      Some(decoded) => bytes_round_trip_eq(data, decoded)
      None => false
    }
  })
  assert_true(ok)
}

///|
test "谓词 · deflate/gzip 往返恒等（PBT）" {
  let ok = @infra_pbt.holds_for_all(gen_bytes(), fn(data) {
    let d = match @infra_compress.inflate(@infra_compress.deflate(data)) {
      Some(x) => bytes_round_trip_eq(data, x)
      None => false
    }
    let g = match
      @infra_compress.gzip_decompress(@infra_compress.gzip_compress(data)) {
      Some(x) => bytes_round_trip_eq(data, x)
      None => false
    }
    d && g
  })
  assert_true(ok)
}

///|
test "谓词 · 流式哈希与一次性哈希一致（PBT）" {
  let ok = @infra_pbt.holds_for_all(gen_bytes(), fn(data) {
    let h = @infra_hash.Sha256Hasher::new()
    // 任意二分切分后分片喂入。
    let cut = data.length() / 2
    let a : Array[Int] = []
    let b : Array[Int] = []
    for k in 0..<data.length() {
      if k < cut {
        a.push(data[k])
      } else {
        b.push(data[k])
      }
    }
    h.update(a)
    h.update(b)
    streaming_matches_oneshot(h.finalize(), @infra_hash.sha256(data))
  })
  assert_true(ok)
}

///|
test "谓词 · 解压炸弹预算有界（定向见证）" {
  let data : Array[Int] = []
  for _k in 0..<500 {
    data.push(3)
  }
  let frame = @infra_compress.zstd_compress(data, false)
  match @infra_compress.zstd_decompress(frame, 1 << 20) {
    Some(out) => assert_true(within_budget(out.length(), 1 << 20))
    None => assert_true(false)
  }
  assert_true(@infra_compress.zstd_decompress(frame, 499) is None)
}

///|
test "谓词 · 多引擎判定一致（Pike VM vs 有界回溯，定向见证）" {
  let cases : Array[(String, String)] = [
    ("a(b|c)*d", "abcbcd"),
    ("(a|b)*abb", "aabb"),
    ("x", "aaa"),
  ]
  for c in cases {
    let (pat, input) = c
    match @regex_engine.parse_regex(pat) {
      Ok(r) => {
        let prog = @regex_engine.compile_program(@regex_engine.Ast::of_regex(r))
        let pike = match prog.exec(input, kind=LeftmostFirst) {
          Some(caps) =>
            match caps.group(0) {
              Some(m) => Some((m.start, m.end))
              None => None
            }
          None => None
        }
        let bt = match prog.exec_backtrack(input) {
          BtMatch(caps) =>
            match caps.group(0) {
              Some(m) => Some((m.start, m.end))
              None => None
            }
          _ => None
        }
        assert_true(spans_agree(pike, bt))
      }
      Err(_) => assert_true(false)
    }
  }
}
