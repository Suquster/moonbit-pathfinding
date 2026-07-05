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

///|
test "bench: span tracer incremental agg vs naive event replay per query" (
  b : @bench.T,
) {
  // 负载：n 个 start/end 事件（确定性随机嵌套 ≤12 层、6 个名字），
  // 每 64 个事件查询一次全部名字的 (count,total,self) 聚合。
  // tracer 侧结束点即时结算、查询 O(名字数)；朴素侧只存事件日志、
  // 每次查询全量回放 O(已有事件数)。
  for n in [8000, 32000, 128000] {
    b.bench(name="span_tracer_incremental_\{n}", fn() {
      let t = @mx.SpanTracer::new()
      let mut acc = 0L
      let mut s = 20260718UL
      let mut now = 0L
      let mut depth = 0
      for i in 0..<n {
        s = xorshift(s)
        now = now + 1L + (s % 40UL).reinterpret_as_int64()
        if depth == 0 || (depth < 12 && (s & 1UL) == 0UL) {
          let _ = t.start("op\{(s % 6UL).to_int()}", now)
          depth = depth + 1
        } else {
          let _ = t.end(now)
          depth = depth - 1
        }
        if i % 64 == 63 {
          for k in 0..<6 {
            match t.stat("op\{k}") {
              Some((c, tt, ss)) => acc = acc + c.to_int64() + tt + ss
              None => ()
            }
          }
        }
      }
      b.keep(acc)
    })
    b.bench(name="naive_replay_per_query_\{n}", fn() {
      let events : Array[(Bool, Int, Int64)] = []
      let mut acc = 0L
      let mut s = 20260718UL
      let mut now = 0L
      let mut depth = 0
      for i in 0..<n {
        s = xorshift(s)
        now = now + 1L + (s % 40UL).reinterpret_as_int64()
        if depth == 0 || (depth < 12 && (s & 1UL) == 0UL) {
          events.push((true, (s % 6UL).to_int(), now))
          depth = depth + 1
        } else {
          events.push((false, 0, now))
          depth = depth - 1
        }
        if i % 64 == 63 {
          // 全量回放重建聚合。
          let count : Array[Int64] = Array::make(6, 0L)
          let total : Array[Int64] = Array::make(6, 0L)
          let selfs : Array[Int64] = Array::make(6, 0L)
          let stack_name : Array[Int] = []
          let stack_start : Array[Int64] = []
          let stack_child : Array[Int64] = []
          for ev in events {
            let (is_start, nm, ts) = ev
            if is_start {
              stack_name.push(nm)
              stack_start.push(ts)
              stack_child.push(0L)
            } else if stack_name.length() > 0 {
              let nm2 = stack_name.unsafe_pop()
              let st = stack_start.unsafe_pop()
              let child = stack_child.unsafe_pop()
              let tt = ts - st
              if stack_child.length() > 0 {
                let k = stack_child.length() - 1
                stack_child[k] = stack_child[k] + tt
              }
              count[nm2] = count[nm2] + 1L
              total[nm2] = total[nm2] + tt
              selfs[nm2] = selfs[nm2] + (tt - child)
            }
          }
          for k in 0..<6 {
            acc = acc + count[k] + total[k] + selfs[k]
          }
        }
      }
      b.keep(acc)
    })
  }
}
