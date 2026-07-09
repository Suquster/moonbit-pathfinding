// codec_alloc_timer_proof_test.mbt —— 编解码/分配器/定时器家族证明谓词的
// 真实实现接地测试。
//
// 以 @infra_codec / @infra_alloc / @infra_timer 的真实包实现驱动
// codec_alloc_timer_proof.mbt 与 predicates.mbt 中的谓词（跨包驱动只发生
// 在测试期）：
//   * CBOR / CSV / hex / UTF-8 / varint / zigzag 往返恒等（随机值 PBT）；
//   * Slab 世代键生命周期（存活键两两互异、iter_live ⊆ 历史 alloc、
//     free 后 contains 为假且计数守恒）；
//   * TimerWheel 触发守恒（触发 id ⊆ 已调度集、id 不复用、
//     触发 + 取消 + 待决 == 已调度总数）。

// --- infra_codec：往返恒等 ---

///|
/// 随机小整数字节数组（值域 0..255，长度 ∈ [0, 24]）。
fn cat_bytes_gen() -> @infra_pbt.Gen[Array[Int]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(0, 24)
    let out : Array[Int] = []
    for _i in 0..<n {
      out.push(rng.next_range(0, 255))
    }
    out
  })
}

///|
test "hex encode/decode round-trips over random byte arrays" {
  let ok = @infra_pbt.holds_for_all(
    cat_bytes_gen(),
    fn(bytes : Array[Int]) -> Bool {
      round_trip_eq(bytes, @infra_codec.hex_encode, @infra_codec.hex_decode)
    },
    iters=128,
  )
  assert_true(ok)
}

///|
test "CBOR encode/decode round-trips over nested values" {
  let v : @infra_codec.CborValue = CborArray([
    CborUInt(42),
    CborNInt(7),
    CborText("路径"),
    CborBytes([1, 2, 3]),
    CborBool(true),
    CborNull,
    CborMap([(CborText("k"), CborArray([CborUInt(0)]))]),
  ])
  assert_true(
    round_trip_eq(v, @infra_codec.cbor_encode, @infra_codec.cbor_decode),
  )
}

///|
fn cat_varint_gen() -> @infra_pbt.Gen[UInt64] {
  @infra_pbt.Gen::new(fn(rng) {
    let hi = rng.next_range(0, 1 << 20).to_uint64()
    let lo = rng.next_range(0, 1 << 20).to_uint64()
    (hi << 20) | lo
  })
}

///|
test "varint and zigzag round-trip via ByteWriter/ByteReader" {
  let ok = @infra_pbt.holds_for_all(
    cat_varint_gen(),
    fn(x : UInt64) -> Bool {
      let fwd = round_trip_eq(
        x,
        fn(v : UInt64) -> Array[Int] {
          let w = @infra_codec.ByteWriter::new()
          w.write_varint(v)
          w.to_bytes()
        },
        fn(bytes : Array[Int]) -> UInt64? {
          @infra_codec.ByteReader::new(bytes).read_varint()
        },
      )
      let signed = x.reinterpret_as_int64() - (1L << 39)
      let zz = round_trip_eq(
        signed,
        fn(v : Int64) -> Array[Int] {
          let w = @infra_codec.ByteWriter::new()
          w.write_zigzag(v)
          w.to_bytes()
        },
        fn(bytes : Array[Int]) -> Int64? {
          @infra_codec.ByteReader::new(bytes).read_zigzag()
        },
      )
      fwd && zz
    },
    iters=128,
  )
  assert_true(ok)
}

///|
test "CSV encode/decode round-trips including quotes and separators" {
  let table = [["a", "b,c", "d\"e"], ["", "换行\n混合", "z"]]
  assert_true(
    round_trip_eq(table, @infra_codec.csv_encode, @infra_codec.csv_decode),
  )
}

///|
test "UTF-8 bytes/string round-trips over mixed-width text" {
  let s = "ascii 与 汉字 mixed"
  assert_true(
    round_trip_eq(
      s, @infra_codec.utf8_bytes_of_string, @infra_codec.string_of_utf8_bytes,
    ),
  )
}

// --- infra_alloc：Slab 世代键生命周期 ---

///|
/// 随机 alloc/free 交错脚本（true = alloc，false = free 最早存活键）。
fn cat_script_gen() -> @infra_pbt.Gen[Array[Bool]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 48)
    let out : Array[Bool] = []
    for _i in 0..<n {
      out.push(rng.next_range(0, 2) > 0)
    }
    out
  })
}

///|
fn cat_prop_slab_lifecycle(script : Array[Bool]) -> Bool {
  let slab : @infra_alloc.Slab[Int] = @infra_alloc.Slab::new()
  let live : Array[@infra_alloc.SlabKey] = []
  let history : Array[Int] = []
  let mut next_val = 0
  let mut allocs = 0
  let mut frees = 0
  for op in script {
    if op || live.length() == 0 {
      let key = slab.alloc(next_val)
      next_val += 1
      allocs += 1
      live.push(key)
      history.push(key.index * 1_000_003 + key.generation)
    } else {
      let key = live[0]
      let _ = live.remove(0)
      if slab.free(key) is None {
        return false
      }
      frees += 1
      if slab.contains(key) {
        return false
      }
    }
  }
  // 世代键全程互异（含已释放的历史键：世代号防复用别名）。
  if !all_distinct(history) {
    return false
  }
  // 存活键集合 == 逐步维护的 live 集，且计数守恒 len == allocs - frees。
  let live_now : Array[Int] = []
  for kv in slab.iter_live() {
    live_now.push(kv.0.index * 1_000_003 + kv.0.generation)
  }
  let live_expect : Array[Int] = []
  for k in live {
    live_expect.push(k.index * 1_000_003 + k.generation)
  }
  subset_of(live_now, live_expect) &&
  subset_of(live_expect, live_now) &&
  count_conserved(slab.len(), [allocs, -frees])
}

///|
test "Slab generation keys stay distinct and live-set is conserved" {
  let ok = @infra_pbt.holds_for_all(
    cat_script_gen(),
    cat_prop_slab_lifecycle,
    iters=128,
  )
  assert_true(ok)
}

///|
test "all_distinct rejects duplicated handles" {
  assert_false(all_distinct([1, 2, 1]))
}

///|
test "subset_of rejects an element outside the source set" {
  assert_false(subset_of([1, 9], [1, 2, 3]))
}

// --- infra_timer：TimerWheel 触发守恒 ---

///|
/// 随机延迟集（长度 ∈ [1, 24]，延迟 ∈ [1, 40] tick），偶数位定时器取消。
fn cat_delays_gen() -> @infra_pbt.Gen[Array[Int]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 24)
    let out : Array[Int] = []
    for _i in 0..<n {
      out.push(rng.next_range(1, 40))
    }
    out
  })
}

///|
fn cat_prop_timer_conservation(delays : Array[Int]) -> Bool {
  let wheel = @infra_timer.TimerWheel::new()
  let scheduled : Array[Int] = []
  for d in delays {
    scheduled.push(wheel.schedule(d))
  }
  // id 不复用。
  if !all_distinct(scheduled) {
    return false
  }
  // 偶数下标取消。
  let mut cancelled = 0
  let mut i = 0
  while i < scheduled.length() {
    if i % 2 == 0 && wheel.cancel(scheduled[i]) {
      cancelled += 1
    }
    i += 2
  }
  // 推进足够多 tick 收集全部触发。
  let fired : Array[Int] = []
  for f in wheel.advance_by(64) {
    fired.push(f)
  }
  // 触发来源封闭 + 触发 id 互异 + 计数守恒。
  subset_of(fired, scheduled) &&
  all_distinct(fired) &&
  count_conserved(scheduled.length(), [
    fired.length(),
    cancelled,
    wheel.pending(),
  ])
}

///|
test "TimerWheel fired ids are unique, sourced from schedule, and conserved" {
  let ok = @infra_pbt.holds_for_all(
    cat_delays_gen(),
    cat_prop_timer_conservation,
    iters=128,
  )
  assert_true(ok)
}
