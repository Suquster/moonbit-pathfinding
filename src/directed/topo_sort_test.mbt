// Blackbox tests for topological sort.

///|
test "topo_sort on DAG returns valid ordering" {
  let nodes = [0, 1, 2, 3]
  let adj : Array[Array[Int]] = [[1, 2], [3], [3], []]
  let result = topological_sort(nodes, fn(n) { adj[n] })
  match result {
    Ok(order) => {
      // 0 must come before 1, 2; 1 and 2 must come before 3.
      let idx : Map[Int, Int] = Map::new()
      for i in 0..<order.length() {
        idx[order[i]] = i
      }
      let ok = idx.get(0).unwrap() < idx.get(1).unwrap() &&
        idx.get(0).unwrap() < idx.get(2).unwrap() &&
        idx.get(1).unwrap() < idx.get(3).unwrap() &&
        idx.get(2).unwrap() < idx.get(3).unwrap()
      inspect(ok, content="true")
    }
    Err(_) => inspect(false, content="true")
  }
}

///|
test "topo_sort on cycle returns error" {
  let nodes = [0, 1, 2]
  let adj : Array[Array[Int]] = [[1], [2], [0]]
  let result = topological_sort(nodes, fn(n) { adj[n] })
  match result {
    Err(CycleDetected) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// whitebox: 空图 —— 所有初始化 for 循环零次,queue 为空,while 不执行,
/// 最终 `result.length() == nodes.length()` 为 0 == 0,走 `Ok(result)` 分支返回 `Ok([])`。
/// 覆盖 `topo_sort.mbt` 中 "空输入直接成功" 的边界路径:
/// in_degree 初始化循环、入度更新循环、种子入队循环、主 while 均不进入循环体。
test "whitebox: topological_sort on empty graph returns Ok empty" {
  let nodes : Array[Int] = []
  let adj : Array[Array[Int]] = []
  let result = topological_sort(nodes, fn(n) { adj[n] })
  match result {
    Ok(order) => inspect(order.length(), content="0")
    Err(_) => inspect(false, content="true")
  }
}
