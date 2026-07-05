// 负例/边界回归（backlog P0）：单节点、不可达、重复后继。

///|
test "bfs_all on single node has distance zero and singleton path" {
  let t = bfs_all(0, fn(_n) { ([] : Array[Int]) })
  assert_true(t.distance_to(0) == Some(0))
  match t.path_to(0) {
    Some(p) => {
      inspect(p.length(), content="1")
      inspect(p[0], content="0")
    }
    None => fail("自身路径应存在")
  }
}

///|
test "bfs_all reports unreachable nodes as None" {
  let t = bfs_all(0, fn(n) { if n == 0 { [1] } else { [] } })
  assert_true(t.distance_to(2) is None)
  assert_true(t.path_to(2) is None)
}

///|
test "bfs_all tolerates duplicate successors without double counting" {
  let t = bfs_all(0, fn(n) { if n == 0 { [1, 1, 1] } else { [] } })
  assert_true(t.distance_to(1) == Some(1))
}
