// infra_metrics_bench.mbt —— E5 DDSketch vs 朴素排序分位 基准。
//
// 负载：流式 n 个样本（确定性 xorshift 混合分布），每 500 个样本查一次
// p99。DDSketch 侧 O(1) add + O(桶数) 查询；朴素侧保存全部样本，每次
// 查询复制 + 排序 O(n log n)。

///|
fn xorshift(x : UInt64) -> UInt64 {
  let mut s = x
  s = s ^ (s << 13)
  s = s ^ (s >> 7)
  s = s ^ (s << 17)
  s
}

///|
fn sample_at(s : UInt64) -> Double {
  let u = ((s % 100000UL).to_int() + 1).to_double()
  u * u / 100000.0 + 1.0 // 重尾（幂次放大）
}

///|
test "bench: ddsketch streaming p99 vs naive sort quantile" (b : @bench.T) {
  for n in [2000, 8000, 32000] {
    b.bench(name="ddsketch_stream_p99_\{n}", fn() {
      let sk = @mx.DDSketch::new(0.01)
      let mut acc = 0.0
      let mut s = 20260713UL
      for i in 0..<n {
        s = xorshift(s)
        sk.add(sample_at(s))
        if i % 500 == 499 {
          match sk.quantile(0.99) {
            Some(v) => acc = acc + v
            None => ()
          }
        }
      }
      b.keep(acc)
    })
    b.bench(name="naive_sort_p99_\{n}", fn() {
      let data : Array[Double] = []
      let mut acc = 0.0
      let mut s = 20260713UL
      for i in 0..<n {
        s = xorshift(s)
        data.push(sample_at(s))
        if i % 500 == 499 {
          let copy = data.copy()
          copy.sort()
          let rank = (0.99 * (copy.length() - 1).to_double()).to_int()
          acc = acc + copy[rank]
        }
      }
      b.keep(acc)
    })
  }
}

///|
test "bench: hdr histogram streaming p999 vs naive sort quantile" (b : @bench.T) {
  for n in [2000, 8000, 32000] {
    b.bench(name="hdr_stream_p999_\{n}", fn() {
      let h = @mx.HdrHistogram::new(7)
      let mut acc = 0L
      let mut s = 20260717UL
      for i in 0..<n {
        s = xorshift(s)
        h.record((s % 1_000_000_000UL).reinterpret_as_int64())
        if i % 500 == 499 {
          match h.value_at_percentile(99.9) {
            Some(v) => acc = acc + v
            None => ()
          }
        }
      }
      b.keep(acc)
    })
    b.bench(name="naive_sort_p999_\{n}", fn() {
      let data : Array[Int64] = []
      let mut acc = 0L
      let mut s = 20260717UL
      for i in 0..<n {
        s = xorshift(s)
        data.push((s % 1_000_000_000UL).reinterpret_as_int64())
        if i % 500 == 499 {
          let copy = data.copy()
          copy.sort()
          let mut rank = (0.999 * copy.length().to_double() + 0.5).to_int()
          if rank > copy.length() {
            rank = copy.length()
          }
          acc = acc + copy[rank - 1]
        }
      }
      b.keep(acc)
    })
  }
}
