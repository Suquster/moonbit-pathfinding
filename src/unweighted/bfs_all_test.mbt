// Tests for full single-source BFS (bfs_all).

///|
test "bfs_all computes hop counts for every reachable node" {
  let adj : Array[Array[Int]] = [[1, 2], [3], [3], [4], [], [0]]
  let tree = bfs_all(0, fn(n : Int) { adj[n] })
  @test.assert_eq(tree.distance_to(0), Some(0))
  @test.assert_eq(tree.distance_to(1), Some(1))
  @test.assert_eq(tree.distance_to(2), Some(1))
  @test.assert_eq(tree.distance_to(3), Some(2))
  @test.assert_eq(tree.distance_to(4), Some(3))
  // Node 5 only points at 0; unreachable from 0.
  @test.assert_eq(tree.distance_to(5), (None : Int?))
  @test.assert_eq(tree.path_to(4), Some([0, 1, 3, 4]))
  @test.assert_eq(tree.path_to(0), Some([0]))
  @test.assert_eq(tree.path_to(5), (None : Array[Int]?))
}

///|
test "bfs_all agrees with goal-directed bfs on path length" {
  let adj : Array[Array[Int]] = [[1, 2], [2, 3], [3], [4], []]
  let tree = bfs_all(0, fn(n : Int) { adj[n] })
  match bfs(0, fn(n : Int) { adj[n] }, fn(n : Int) { n == 4 }) {
    Some(path) => @test.assert_eq(tree.distance_to(4), Some(path.length() - 1))
    None => assert_true(false)
  }
}
