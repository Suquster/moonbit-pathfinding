// prop_lin_corpus_test.mbt —— T8.3 线性一致性检查器对标 Knossos 的正/反例语料。
//
// 两部分：
//   1. **已知语料**：Herlihy & Wing 1990 / Jepsen-Knossos 经典正反例——
//      并发重叠读写的双向合法线性化、过期读（stale read）、超前读
//      （future read，读到实时晚于自身返回才开始的写）。
//   2. **差分 PBT**（100 迭代）：按构造生成真·线性一致的并发历史（为每个操作
//      显式指定单调递增的线性化点，调用/返回时间在点两侧随机展开、跨进程重叠），
//      检查器必判 Linearizable；再对其中随机一个 get 注入从未写入过的值
//      （stale/幽灵读），必判 NotLinearizable 且冲突集非空。

///|
test "Feature: dst, Corpus: overlapping put/get admits both linearization orders (H&W)" {
  let model : RegisterModel = { init: 0 }
  // put(1) 与 get 并发重叠：get 读 0（先 get 后 put）与读 1（先 put 后 get）
  // 均线性一致。
  for read in [0, 1] {
    let h : Array[OpEvent] = [
      OpEvent::invoke(0, "put", 1, 0UL),
      OpEvent::invoke(1, "get", 0, 1UL),
      OpEvent::ret(0, "put", 0, 5UL),
      OpEvent::ret(1, "get", read, 6UL),
    ]
    assert_true(is_linearizable(h, model) is Linearizable)
  }
  // 并发窗口外的值（从未写入）不可线性化。
  let h : Array[OpEvent] = [
    OpEvent::invoke(0, "put", 1, 0UL),
    OpEvent::invoke(1, "get", 0, 1UL),
    OpEvent::ret(0, "put", 0, 5UL),
    OpEvent::ret(1, "get", 7, 6UL),
  ]
  assert_true(is_linearizable(h, model) is NotLinearizable(..))
}

///|
test "Feature: dst, Corpus: stale read after both writes complete is rejected (Knossos)" {
  let model : RegisterModel = { init: 0 }
  // 两个并发 put(1)/put(2) 全部返回后，get=1 再 get=2：第二个 get 读到
  // 已被覆盖顺序中更早的值——两种 put 排序都无法同时满足，非线性一致。
  let h : Array[OpEvent] = [
    OpEvent::invoke(0, "put", 1, 0UL),
    OpEvent::invoke(1, "put", 2, 1UL),
    OpEvent::ret(0, "put", 0, 2UL),
    OpEvent::ret(1, "put", 0, 3UL),
    OpEvent::invoke(2, "get", 0, 4UL),
    OpEvent::ret(2, "get", 1, 5UL),
    OpEvent::invoke(2, "get", 0, 6UL),
    OpEvent::ret(2, "get", 2, 7UL),
  ]
  assert_true(is_linearizable(h, model) is NotLinearizable(..))
  // 而 get=2 后 get=2（put1 先、put2 后的合法排序）线性一致。
  let h2 : Array[OpEvent] = [
    OpEvent::invoke(0, "put", 1, 0UL),
    OpEvent::invoke(1, "put", 2, 1UL),
    OpEvent::ret(0, "put", 0, 2UL),
    OpEvent::ret(1, "put", 0, 3UL),
    OpEvent::invoke(2, "get", 0, 4UL),
    OpEvent::ret(2, "get", 2, 5UL),
    OpEvent::invoke(2, "get", 0, 6UL),
    OpEvent::ret(2, "get", 2, 7UL),
  ]
  assert_true(is_linearizable(h2, model) is Linearizable)
}

///|
test "Feature: dst, Corpus: future read (write starts after read returns) is rejected" {
  let model : RegisterModel = { init: 0 }
  // get 在 put(5) 开始之前已返回，却读到 5：违反实时先后序。
  let h : Array[OpEvent] = [
    OpEvent::invoke(0, "get", 0, 0UL),
    OpEvent::ret(0, "get", 5, 1UL),
    OpEvent::invoke(1, "put", 5, 2UL),
    OpEvent::ret(1, "put", 0, 3UL),
  ]
  assert_true(is_linearizable(h, model) is NotLinearizable(..))
}

///|
/// 按构造生成真·线性一致的并发历史：n 个操作的线性化点取 10,20,…,10n，
/// 每个操作的调用/返回时间在线性化点两侧随机展开（跨进程可重叠），同进程
/// 串行（调用不早于上一次返回）。返回 (事件按时间排序的历史, 写入值上界)。
fn gen_linearizable_history(
  rng : @infra_pbt.Rng,
  n : Int,
  procs : Int,
) -> Array[OpEvent] {
  let last_ret : Array[Int] = Array::make(procs, -1)
  let mut state = 0
  let timed : Array[(Int, Int, OpEvent)] = [] // (time, tie, event)
  for i in 0..<n {
    let p = rng.next_below(procs)
    let lp = 10 * (i + 1)
    let inv_lo = last_ret[p] + 1
    let mut inv = lp - rng.next_range(0, 8)
    if inv < inv_lo {
      inv = inv_lo
    }
    if inv > lp {
      inv = lp
    }
    let ret_t = lp + rng.next_range(0, 8)
    last_ret[p] = ret_t
    if rng.next_bool() {
      let v = rng.next_range(1, 99)
      state = v
      timed.push((inv, 0, OpEvent::invoke(p, "put", v, inv.to_uint64())))
      timed.push((ret_t, 1, OpEvent::ret(p, "put", 0, ret_t.to_uint64())))
    } else {
      timed.push((inv, 0, OpEvent::invoke(p, "get", 0, inv.to_uint64())))
      timed.push((ret_t, 1, OpEvent::ret(p, "get", state, ret_t.to_uint64())))
    }
  }
  // 按 (time, invoke 优先) 稳定排序，保证同进程调用先于返回。
  timed.sort_by(fn(a, b) {
    let (ta, ka, _) = a
    let (tb, kb, _) = b
    if ta != tb {
      ta - tb
    } else {
      ka - kb
    }
  })
  timed.map(fn(t) {
    let (_, _, e) = t
    e
  })
}

///|
test "Feature: dst, Property: constructed linearizable histories pass; ghost-read mutants fail" {
  let rng = @infra_pbt.rng_new(20260705UL)
  let model : RegisterModel = { init: 0 }
  for _ in 0..<100 {
    let h = gen_linearizable_history(rng, 6, 3)
    assert_true(is_linearizable(h, model) is Linearizable)
    // 变异：随机挑一个 get 返回事件，注入从未写入过的幽灵值 777。
    let idxs : Array[Int] = []
    for i in 0..<h.length() {
      if h[i].kind == Return && h[i].op == "get" {
        idxs.push(i)
      }
    }
    if idxs.length() > 0 {
      let i = idxs[rng.next_below(idxs.length())]
      let bad : Array[OpEvent] = []
      for j in 0..<h.length() {
        if j == i {
          bad.push(OpEvent::ret(h[j].proc, "get", 777, h[j].time))
        } else {
          bad.push(h[j])
        }
      }
      match is_linearizable(bad, model) {
        NotLinearizable(conflict~) => assert_true(conflict.length() > 0)
        Linearizable => fail("幽灵读变异历史不应线性一致")
      }
    }
  }
}
