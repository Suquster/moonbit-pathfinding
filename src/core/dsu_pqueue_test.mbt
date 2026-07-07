// dsu_pqueue_test.mbt —— core 包补充覆盖：DSU 全 API、PQueue 堆序、
// PathError 相等语义。

///|
test "dsu union find with path compression semantics" {
  let d : DSU[Int] = DSU::new()
  for i in 0..<8 {
    d.make_set(i)
  }
  // 初始各自为根。
  assert_true(!d.same(0, 1))
  @test.assert_eq(d.find(3), 3)
  // union 返回 true 表示发生合并，false 表示已同集。
  assert_true(d.union(0, 1))
  assert_true(d.union(1, 2))
  assert_true(!d.union(0, 2))
  assert_true(d.same(0, 2))
  assert_true(!d.same(0, 3))
  // 两棵树合并。
  assert_true(d.union(3, 4))
  assert_true(d.union(2, 4))
  assert_true(d.same(1, 3))
  // find 幂等且同集同根。
  @test.assert_eq(d.find(0), d.find(4))
  @test.assert_eq(d.find(0), d.find(d.find(0)))
  // 未接触的元素不受影响。
  assert_true(!d.same(5, 0))
  assert_true(d.same(5, 5))
}

///|
test "dsu works with string keys" {
  let d : DSU[String] = DSU::new()
  d.make_set("a")
  d.make_set("b")
  d.make_set("c")
  assert_true(d.union("a", "b"))
  assert_true(d.same("a", "b"))
  assert_true(!d.same("a", "c"))
}

///|
test "pqueue pops in ascending weight order" {
  let q : PQueue[String, Int] = PQueue::new()
  q.push(5, "e")
  q.push(1, "a")
  q.push(3, "c")
  q.push(2, "b")
  q.push(4, "d")
  let order : Array[String] = []
  while !q.is_empty() {
    match q.pop() {
      Some((_, n)) => order.push(n)
      None => ()
    }
  }
  assert_true(order == ["a", "b", "c", "d", "e"])
}

///|
test "pqueue peek does not remove and duplicate weights are stable-safe" {
  let q : PQueue[Int, Int] = PQueue::new()
  q.push(7, 70)
  q.push(7, 71)
  match q.peek() {
    Some((w, _)) => @test.assert_eq(w, 7)
    None => abort("peek should succeed")
  }
  @test.assert_eq(q.len(), 2)
  // 两个同权元素都能弹出。
  assert_true(q.pop() is Some(_))
  assert_true(q.pop() is Some(_))
  assert_true(q.pop() is None)
}

///|
test "pqueue heap order (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<100 {
    let q : PQueue[Int, Int] = PQueue::new()
    let n = 1 + rng.next_below(50)
    for i in 0..<n {
      q.push(rng.next_below(1000), i)
    }
    @test.assert_eq(q.len(), n)
    let mut prev = -1
    while !q.is_empty() {
      match q.pop() {
        Some((w, _)) => {
          assert_true(w >= prev)
          prev = w
        }
        None => abort("non-empty queue must pop")
      }
    }
  }
}

///|
test "path error equality" {
  assert_true(PathError::NegativeCycle == PathError::NegativeCycle)
  assert_true(PathError::InvalidK(3) == PathError::InvalidK(3))
  assert_true(PathError::InvalidK(3) != PathError::InvalidK(4))
  assert_true(PathError::InvalidInput("x") != PathError::CycleDetected)
}

///|
test "int weight zero and add semantics" {
  let z : Int = Weight::zero()
  @test.assert_eq(z, 0)
  @test.assert_eq(Weight::add(2, 3), 5)
  let inf : Int = Weight::infinity()
  // 加法不溢出穿透 infinity。
  @test.assert_eq(Weight::add(inf, 1), inf)
  let dz : Double = Weight::zero()
  @test.assert_eq(dz, 0.0)
}
