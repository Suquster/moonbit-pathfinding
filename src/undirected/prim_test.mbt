// Blackbox tests for Prim MST.

///|
fn adjacency(edges : Array[(Int, Int, Int)]) -> (Int) -> Array[(Int, Int)] {
  fn(u) {
    let out : Array[(Int, Int)] = []
    for e in edges {
      let (a, b, w) = e
      if a == u {
        out.push((b, w))
      } else if b == u {
        out.push((a, w))
      }
    }
    out
  }
}

///|
test "prim builds MST on 4-node cycle" {
  // Graph: 0-1 (w=1), 1-2 (w=2), 2-3 (w=3), 3-0 (w=4)
  // MST should pick 0-1, 1-2, 2-3 (total weight 6)
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (1, 2, 2),
    (2, 3, 3),
    (3, 0, 4),
  ]
  let mst = prim_mst(nodes, adjacency(edges))
  let total = mst.fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  inspect(total, content="6")
  inspect(mst.length(), content="3")
}

///|
test "prim on disconnected graph returns forest" {
  // Two components: {0,1} and {2,3}
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1), (2, 3, 2)]
  let mst = prim_mst(nodes, adjacency(edges))
  inspect(mst.length(), content="2")
}

///|
test "prim on isolated nodes returns empty edge set" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = []
  let mst = prim_mst(nodes, adjacency(edges))
  inspect(mst.length(), content="0")
}

///|
test "prim picks minimum among parallel edges" {
  // Parallel edges (0,1): 10 / 1 / 5, plus (1,2,2).
  // MST total must be 3.
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 10),
    (0, 1, 1),
    (0, 1, 5),
    (1, 2, 2),
  ]
  let mst = prim_mst(nodes, adjacency(edges))
  inspect(mst.length(), content="2")
  let total = mst.fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  inspect(total, content="3")
}

///|
test "prim agrees with kruskal on a dense graph" {
  // Complete graph K5 with deterministic pseudo-random weights.
  let nodes = [0, 1, 2, 3, 4]
  let edges : Array[(Int, Int, Int)] = []
  for i in 0..<5 {
    for j in (i + 1)..<5 {
      edges.push((i, j, (i * 7 + j * 13) % 11 + 1))
    }
  }
  let prim_total = prim_mst(nodes, adjacency(edges)).fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  let kruskal_total = kruskal_mst(nodes, edges).fold(init=0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  @test.assert_eq(prim_total, kruskal_total)
}

///|
test "prim works with Double weights" {
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.5),
    (1, 2, 2.5),
    (0, 2, 5.0),
  ]
  let neighbors = fn(u : Int) {
    let out : Array[(Int, Double)] = []
    for e in edges {
      let (a, b, w) = e
      if a == u {
        out.push((b, w))
      } else if b == u {
        out.push((a, w))
      }
    }
    out
  }
  let mst = prim_mst(nodes, neighbors)
  let total = mst.fold(init=0.0, fn(acc, e) {
    let (_, _, w) = e
    acc + w
  })
  inspect(total, content="4")
  inspect(mst.length(), content="2")
}
