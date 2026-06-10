// Blackbox tests for Yen's K-shortest paths.

///|
test "yen k=1 equals dijkstra" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (0, 2, 2),
    (1, 3, 5),
    (2, 3, 3),
  ]
  let result = yen_k_shortest(0, 3, edges, 1)
  match result {
    Ok(paths) => {
      inspect(paths.length(), content="1")
      let first = paths[0]
      inspect(first.1, content="5")
    }
    Err(_) => inspect(false, content="true")
  }
}

///|
test "yen k=0 returns error" {
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1)]
  let result = yen_k_shortest(0, 1, edges, 0)
  match result {
    Err(InvalidK(0)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "yen paths sorted by cost" {
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (0, 2, 2),
    (1, 3, 5),
    (2, 3, 3),
  ]
  let result = yen_k_shortest(0, 3, edges, 3)
  match result {
    Ok(paths) => {
      let mut ok = true
      let mut i = 1
      while i < paths.length() {
        if paths[i - 1].1 > paths[i].1 {
          ok = false
        }
        i += 1
      }
      inspect(ok, content="true")
    }
    Err(_) => inspect(false, content="true")
  }
}

///|
/// whitebox: k=3 但图上仅存在 1 条可达路径 —— 触发 `candidates.length() == 0 { break }` 冷分支。
/// 图为一条链 0 -> 1 -> 2,无备选边。第一次 accept 唯一的 shortest 后进入 ki=1 的 while 迭代:
/// 对每个 spur 点构造 banned edges/nodes 后调用 dijkstra,所有 spur 结果要么 None、要么生成
/// 违反 banned_nodes 的路径 -> candidates 保持为空。随即命中
/// `if candidates.length() == 0 { break }`,结果长度停留在 1。
/// 覆盖 `yen.mbt` 主 while 末尾的提前 break 路径与 `None => ()` 冷边。
test "whitebox: yen breaks out of loop when candidates exhausted" {
  // 唯一可达路径: 0 -> 1 -> 2。无备选边,第 2 条 k 找不到。
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (1, 2, 1)]
  let result = yen_k_shortest(0, 2, edges, 3)
  match result {
    Ok(paths) => {
      // 只能找到 1 条路径,即便请求 k=3。
      inspect(paths.length(), content="1")
      inspect(paths[0].0, content="[0, 1, 2]")
      inspect(paths[0].1, content="2")
    }
    Err(_) => inspect(false, content="true")
  }
}
