// Runtime tests for bfs_proof.mbt post-condition predicates.
//
// These prove the predicates themselves behave correctly on concrete
// inputs. Once `moon prove` matures and `#ensures(bfs_post(...))` lands
// on `@uw.bfs`, these tests remain as a safety net for the predicate
// definitions.

///|
test "check_starts_at_start passes for valid BFS output" {
  let result : Array[Int]? = Some([0, 1, 2])
  inspect(check_starts_at_start(result, 0), content="true")
}

///|
test "check_starts_at_start fails when first node wrong" {
  let result : Array[Int]? = Some([1, 2])
  inspect(check_starts_at_start(result, 0), content="false")
}

///|
test "check_starts_at_start vacuously true for None" {
  let result : Array[Int]? = None
  inspect(check_starts_at_start(result, 0), content="true")
}

///|
test "check_ends_at_goal passes when last satisfies predicate" {
  let result : Array[Int]? = Some([0, 1, 3])
  inspect(check_ends_at_goal(result, fn(n) { n == 3 }), content="true")
}

///|
test "check_ends_at_goal fails when last does not satisfy predicate" {
  let result : Array[Int]? = Some([0, 1, 2])
  inspect(check_ends_at_goal(result, fn(n) { n == 3 }), content="false")
}

///|
test "check_edges_valid accepts well-formed chain" {
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let result : Array[Int]? = Some([0, 1, 2, 3])
  inspect(check_edges_valid(result, 0, fn(n) { adj[n] }), content="true")
}

///|
test "check_minimality accepts a shortest path" {
  let adj : Array[Array[Int]] = [[1, 2], [3], [3], []]
  let result : Array[Int]? = Some([0, 1, 3])
  inspect(
    check_minimality(result, 0, fn(n) { adj[n] }, fn(n) { n == 3 }),
    content="true",
  )
}

///|
test "check_minimality rejects a longer valid path" {
  let adj : Array[Array[Int]] = [[1, 2], [3], [4], [], [3]]
  let result : Array[Int]? = Some([0, 2, 4, 3])
  inspect(
    check_minimality(result, 0, fn(n) { adj[n] }, fn(n) { n == 3 }),
    content="false",
  )
}

///|
test "check_minimality rejects invalid paths" {
  let adj : Array[Array[Int]] = [[1], [2], []]
  let result : Array[Int]? = Some([0, 2])
  inspect(
    check_minimality(result, 0, fn(n) { adj[n] }, fn(n) { n == 2 }),
    content="false",
  )
}

///|
test "check_none_witness passes when graph really has no path" {
  let adj : Array[Array[Int]] = [[1], [], []]
  let result : Array[Int]? = None
  inspect(
    check_none_witness(result, 0, fn(n) { adj[n] }, fn(n) { n == 2 }, [0, 1, 2]),
    content="true",
  )
}

///|
test "bfs_post aggregate passes when all POST-K pass" {
  let adj : Array[Array[Int]] = [[1], [2], [3], []]
  let result : Array[Int]? = Some([0, 1, 2, 3])
  inspect(
    bfs_post(result, 0, fn(n) { adj[n] }, fn(n) { n == 3 }, [0, 1, 2, 3]),
    content="true",
  )
}

///|
test "bad witness: bfs_post rejects a non-minimal returned path" {
  let adj : Array[Array[Int]] = [[1, 2], [3], [4], [], [3]]
  let result : Array[Int]? = Some([0, 2, 4, 3])
  inspect(
    bfs_post(result, 0, fn(n) { adj[n] }, fn(n) { n == 3 }, [0, 1, 2, 3, 4]),
    content="false",
  )
}

///|
test "bad witness: bfs_post rejects None when a goal is reachable" {
  let adj : Array[Array[Int]] = [[1], [2], []]
  let result : Array[Int]? = None
  inspect(
    bfs_post(result, 0, fn(n) { adj[n] }, fn(n) { n == 2 }, [0, 1, 2]),
    content="false",
  )
}
