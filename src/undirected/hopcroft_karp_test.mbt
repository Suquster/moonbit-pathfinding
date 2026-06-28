// Tests for Hopcroft-Karp maximum bipartite matching.

///|
test "hopcroft_karp finds a perfect matching" {
  let left = [0, 1, 2]
  let right = [10, 11, 12]
  let adj = fn(l : Int) -> Array[Int] {
    match l {
      0 => [10, 11]
      1 => [10]
      2 => [11, 12]
      _ => []
    }
  }
  let matching = hopcroft_karp(left, right, adj)
  @test.assert_eq(matching.length(), 3)
  // Every pair must be a real edge; sides must be distinct.
  let seen_l : Map[Int, Bool] = Map([])
  let seen_r : Map[Int, Bool] = Map([])
  for pair in matching {
    let (l, r) = pair
    let mut is_edge = false
    for cand in adj(l) {
      if cand == r {
        is_edge = true
        break
      }
    }
    assert_true(is_edge)
    assert_true(!seen_l.contains(l))
    assert_true(!seen_r.contains(r))
    seen_l[l] = true
    seen_r[r] = true
  }
}

///|
test "hopcroft_karp needs augmenting paths to reach the maximum" {
  // Greedy matching 0-10 would block 1; the algorithm must re-route.
  let left = [0, 1]
  let right = [10, 11]
  let adj = fn(l : Int) -> Array[Int] {
    match l {
      0 => [10, 11]
      1 => [10]
      _ => []
    }
  }
  @test.assert_eq(hopcroft_karp(left, right, adj).length(), 2)
}

///|
test "hopcroft_karp handles imbalance and unknown neighbors" {
  // Right side smaller than left; one neighbor not in `right` is ignored.
  let left = [0, 1, 2]
  let right = [10]
  let adj = fn(l : Int) -> Array[Int] {
    match l {
      0 => [10, 99]
      1 => [10]
      2 => []
      _ => []
    }
  }
  @test.assert_eq(hopcroft_karp(left, right, adj).length(), 1)
  // Empty partitions.
  @test.assert_eq(
    hopcroft_karp(([] : Array[Int]), ([] : Array[Int]), fn(_) {
      ([] : Array[Int])
    }).length(),
    0,
  )
}
