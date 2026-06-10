// Blackbox tests for Kruskal MST.

///|
test "kruskal builds MST on 4-node cycle" {
  // Graph: 0-1 (w=1), 1-2 (w=2), 2-3 (w=3), 3-0 (w=4)
  // MST should pick 0-1, 1-2, 2-3 (total weight 6)
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (1, 2, 2),
    (2, 3, 3),
    (3, 0, 4),
  ]
  let mst = kruskal_mst(nodes, edges)
  let total = mst.fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  inspect(total, content="6")
  inspect(mst.length(), content="3")
}

///|
test "kruskal on disconnected graph returns forest" {
  // Two components: {0,1} and {2,3}
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (2, 3, 2)]
  let mst = kruskal_mst(nodes, edges)
  inspect(mst.length(), content="2")
}

///|
test "kruskal on isolated nodes returns empty edge set" {
  // 4 个孤立节点,无任何边 -> MST 为空 (每个节点自成一个分量)
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = []
  let mst = kruskal_mst(nodes, edges)
  inspect(mst.length(), content="0")
  let total = mst.fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  inspect(total, content="0")
}

///|
test "kruskal picks minimum among parallel edges" {
  // 同一对节点 (0,1) 提供 3 条不同权边: 10 / 1 / 5
  // 另加一条 (1,2,2); 正确 MST 应为 {(0,1,1),(1,2,2)}, 总权 3
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 10),
    (0, 1, 1),
    (0, 1, 5),
    (1, 2, 2),
  ]
  let mst = kruskal_mst(nodes, edges)
  inspect(mst.length(), content="2")
  let total = mst.fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  inspect(total, content="3")
}

///|
/// whitebox: 多条等权边 — 验证 sort_by 在 wa == wb 时返回 0 的分支,
/// 并确保 DSU 在遇到已联通的等权边时正确返回 false(不加入 MST)。
/// 覆盖 `kruskal.mbt` 中比较器的 `0` 分支 与 `dsu.union == false` 跳过分支。
test "whitebox: kruskal handles equal-weight edges deterministically" {
  // 三角形三边同权 w=1, 再加一条指向 3 的 w=2 边。
  //   0 --1-- 1
  //   1 --1-- 2
  //   2 --1-- 0   (三条等权边中必有一条会被 DSU 跳过)
  //   2 --2-- 3
  // 正确 MST: 选择两条 w=1 边 + 一条 w=2 边,总权 = 4,边数 = 3。
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (1, 2, 1),
    (2, 0, 1),
    (2, 3, 2),
  ]
  let mst = kruskal_mst(nodes, edges)
  inspect(mst.length(), content="3")
  let total = mst.fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  inspect(total, content="4")
}
