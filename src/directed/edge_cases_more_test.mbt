// 负例/边界回归补充（backlog P0）：非法输入、不可达、零/单节点、不连通。

///|
test "yen rejects non-positive k with InvalidK" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1)]
  assert_true(yen_k_shortest(0, 1, edges, 0) is Err(InvalidK(0)))
  assert_true(yen_k_shortest(0, 1, edges, -3) is Err(InvalidK(-3)))
}

///|
test "yen on unreachable goal returns empty path list" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (2, 3, 1)]
  match yen_k_shortest(0, 3, edges, 4) {
    Ok(paths) => inspect(paths.length(), content="0")
    Err(_) => fail("不可达应返回 Ok([])")
  }
}

///|
test "topological_sort on empty node set is empty" {
  match topological_sort(([] : Array[Int]), fn(_n) { ([] : Array[Int]) }) {
    Ok(order) => inspect(order.length(), content="0")
    Err(_) => fail("空图拓扑排序应成功")
  }
}

///|
test "topological_sort on single node yields singleton order" {
  match topological_sort([9], fn(_n) { ([] : Array[Int]) }) {
    Ok(order) => {
      inspect(order.length(), content="1")
      inspect(order[0], content="9")
    }
    Err(_) => fail("单节点拓扑排序应成功")
  }
}

///|
test "topological_sort flags a self-loop as a cycle" {
  assert_true(topological_sort([0], fn(_n) { [0] }) is Err(CycleDetected))
}

///|
test "edmonds_karp with disconnected sink yields zero flow" {
  let cap : Map[(Int, Int), Int] = Map([((0, 1), 5)])
  inspect(edmonds_karp([0, 1, 2], cap, 0, 2), content="0")
}

///|
test "edmonds_karp source equals sink yields zero flow" {
  let cap : Map[(Int, Int), Int] = Map([((0, 1), 5)])
  inspect(edmonds_karp([0, 1], cap, 0, 0), content="0")
}
