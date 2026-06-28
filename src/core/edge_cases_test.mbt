// Blackbox edge-case tests for the core package: PQueue boundary
// behaviour and Weight saturation semantics for Int / Double.

///|
test "pqueue len tracks pushes and pops" {
  let q : PQueue[Int, Int] = PQueue::new()
  @test.assert_eq(q.len(), 0)
  q.push(3, 30)
  q.push(1, 10)
  @test.assert_eq(q.len(), 2)
  ignore(q.pop())
  @test.assert_eq(q.len(), 1)
}

///|
test "pqueue pop and peek on empty queue return None" {
  let q : PQueue[Int, Int] = PQueue::new()
  assert_true(q.pop() is None)
  assert_true(q.peek() is None)
}

///|
test "double weight infinity absorbs addition" {
  let inf : Double = Weight::infinity()
  assert_true(inf > 1.0e300)
  @test.assert_eq(Weight::add(inf, 5.0), inf)
}

///|
test "double weight sub clamps negative results to zero" {
  let d : Double = Weight::sub(3.0, 5.0)
  @test.assert_eq(d, 0.0)
  let e : Double = Weight::sub(5.0, 3.0)
  @test.assert_eq(e, 2.0)
}

///|
test "int weight sub saturates at zero and preserves infinity" {
  let z : Int = Weight::sub(3, 5)
  @test.assert_eq(z, 0)
  let inf : Int = Weight::infinity()
  let still_inf : Int = Weight::sub(inf, 100)
  @test.assert_eq(still_inf, inf)
}
