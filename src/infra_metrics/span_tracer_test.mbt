// span_tracer_test.mbt —— SpanTracer 黑盒测试：定向（嵌套/self-total 结算/
// 树形）+ 与朴素事件回放差分 PBT + 确定性重放。

///|
test "span tracer basic: nesting, total/self accounting, tree shape" {
  let t = @infra_metrics.SpanTracer::new()
  // a[0..100] { b[10..40] { c[20..30] } b2[50..90] }
  let a = t.start("a", 0L)
  assert_eq(t.active_depth(), 1)
  let b = t.start("b", 10L)
  let c = t.start("c", 20L)
  assert_eq(t.active_depth(), 3)
  assert_eq(t.end(30L), c)
  assert_eq(t.end(40L), b)
  let b2 = t.start("b", 50L)
  assert_eq(t.end(90L), b2)
  assert_eq(t.end(100L), a)
  assert_eq(t.active_depth(), 0)
  assert_eq(t.finished_count(), 4)
  // total/self。
  assert_true(t.span_total(a) == Some(100L))
  assert_true(t.span_self(a) == Some(100L - 30L - 40L))
  assert_true(t.span_total(b) == Some(30L))
  assert_true(t.span_self(b) == Some(20L))
  assert_true(t.span_total(c) == Some(10L))
  assert_true(t.span_self(c) == Some(10L))
  // 聚合：b 出现 2 次，total=30+40，self=20+40。
  assert_true(t.stat("b") == Some((2, 70L, 60L)))
  assert_true(t.stat("a") == Some((1, 100L, 30L)))
  assert_true(t.stat("missing") is None)
  // 树形。
  assert_true(t.root_spans() == [a])
  assert_true(t.children_of(a) == [b, b2])
  assert_true(t.children_of(b) == [c])
  assert_true(t.span_name(c) == Some("c"))
}

///|
test "span tracer: multiple roots and unfinished spans" {
  let t = @infra_metrics.SpanTracer::new()
  let r1 = t.start("r", 0L)
  assert_eq(t.end(5L), r1)
  let r2 = t.start("r", 10L)
  let child = t.start("x", 12L)
  assert_true(t.root_spans() == [r1, r2])
  // 未结束 span 无 total/self；end 空栈返回 -1。
  assert_true(t.span_total(child) is None)
  assert_eq(t.end(20L), child)
  assert_eq(t.end(30L), r2)
  assert_eq(t.end(99L), -1)
  assert_true(t.stat("r") == Some((2, 25L, 17L)))
}

///|
/// 朴素参照：从事件日志（true=start(name,ts) / false=end(ts)）全量回放，
/// 重建每名字 (count, total, self)。
fn naive_replay(
  events : Array[(Bool, String, Int64)],
) -> Map[String, (Int, Int64, Int64)] {
  let out : Map[String, (Int, Int64, Int64)] = Map([])
  // 栈：( name, start_ts, child_time )。
  let stack : Array[(String, Int64, Int64)] = []
  let stack_child : Array[Int64] = []
  for ev in events {
    let (is_start, name, ts) = ev
    if is_start {
      stack.push((name, ts, 0L))
      stack_child.push(0L)
    } else {
      match stack.pop() {
        None => ()
        Some((nm, st, _)) => {
          let child = match stack_child.pop() {
            Some(cv) => cv
            None => 0L
          }
          let total = ts - st
          let self_time = total - child
          if stack_child.length() > 0 {
            let k = stack_child.length() - 1
            stack_child[k] = stack_child[k] + total
          }
          match out.get(nm) {
            Some((c, tt, ss)) =>
              out.set(nm, (c + 1, tt + total, ss + self_time))
            None => out.set(nm, (1, total, self_time))
          }
        }
      }
    }
  }
  out
}

///|
test "span tracer differential PBT vs naive event replay (200 iterations)" {
  let rng = @infra_pbt.rng_new(0xE5_59A2UL)
  for _iter in 0..<200 {
    let t = @infra_metrics.SpanTracer::new()
    let events : Array[(Bool, String, Int64)] = []
    let mut now = 0L
    let mut depth = 0
    let steps = 10 + rng.next_below(120)
    for _step in 0..<steps {
      now = now + (1 + rng.next_below(50)).to_int64()
      if depth == 0 || (depth < 12 && rng.next_below(2) == 0) {
        let name = "op\{rng.next_below(6)}"
        let _ = t.start(name, now)
        events.push((true, name, now))
        depth = depth + 1
      } else {
        let _ = t.end(now)
        events.push((false, "", now))
        depth = depth - 1
      }
    }
    // 收尾：结束全部活动 span。
    while depth > 0 {
      now = now + 1L
      let _ = t.end(now)
      events.push((false, "", now))
      depth = depth - 1
    }
    let expect = naive_replay(events)
    assert_eq(
      t.finished_count(),
      {
        let mut c = 0
        for _, v in expect {
          c = c + v.0
        }
        c
      },
    )
    for name, v in expect {
      assert_true(t.stat(name) == Some(v))
    }
    assert_eq(t.stat_names().length(), expect.length())
  }
}

///|
test "span tracer: deterministic replay (same events => identical stats)" {
  fn run() -> (Int, Int64, Int64) {
    let t = @infra_metrics.SpanTracer::new()
    let rng = @infra_pbt.rng_new(0x5EEDUL)
    let mut now = 0L
    let mut depth = 0
    for _ in 0..<300 {
      now = now + (1 + rng.next_below(9)).to_int64()
      if depth == 0 || rng.next_below(2) == 0 {
        let _ = t.start("op\{rng.next_below(3)}", now)
        depth = depth + 1
      } else {
        let _ = t.end(now)
        depth = depth - 1
      }
    }
    while depth > 0 {
      now = now + 1L
      let _ = t.end(now)
      depth = depth - 1
    }
    match t.stat("op0") {
      Some(v) => v
      None => (0, 0L, 0L)
    }
  }

  assert_true(run() == run())
}
