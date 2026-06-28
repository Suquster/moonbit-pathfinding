// Blackbox tests for bridges and articulation points.

///|
fn undirected_adj(edges : Array[(Int, Int)]) -> (Int) -> Array[Int] {
  fn(u) {
    let out : Array[Int] = []
    for e in edges {
      let (a, b) = e
      if a == u {
        out.push(b)
      } else if b == u {
        out.push(a)
      }
    }
    out
  }
}

///|
test "bridge in a barbell graph" {
  // Two triangles {0,1,2} and {3,4,5} joined by bridge 2-3.
  let nodes = [0, 1, 2, 3, 4, 5]
  let edges : Array[(Int, Int)] = [
    (0, 1),
    (1, 2),
    (2, 0),
    (2, 3),
    (3, 4),
    (4, 5),
    (5, 3),
  ]
  let result = bridges(nodes, undirected_adj(edges))
  inspect(result.length(), content="1")
  let (u, v) = result[0]
  assert_true((u == 2 && v == 3) || (u == 3 && v == 2))
  let cuts = articulation_points(nodes, undirected_adj(edges))
  cuts.sort()
  @debug.debug_inspect(cuts, content="[2, 3]")
}

///|
test "cycle has no bridges or articulation points" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 0)]
  inspect(bridges(nodes, undirected_adj(edges)).length(), content="0")
  inspect(
    articulation_points(nodes, undirected_adj(edges)).length(),
    content="0",
  )
}

///|
test "every edge of a path is a bridge" {
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int)] = [(0, 1), (1, 2), (2, 3)]
  inspect(bridges(nodes, undirected_adj(edges)).length(), content="3")
  let cuts = articulation_points(nodes, undirected_adj(edges))
  cuts.sort()
  @debug.debug_inspect(cuts, content="[1, 2]")
}

///|
test "star graph center is the only articulation point" {
  let nodes = [0, 1, 2, 3, 4]
  let edges : Array[(Int, Int)] = [(0, 1), (0, 2), (0, 3), (0, 4)]
  let cuts = articulation_points(nodes, undirected_adj(edges))
  @debug.debug_inspect(cuts, content="[0]")
  inspect(bridges(nodes, undirected_adj(edges)).length(), content="4")
}

///|
test "parallel edges are never bridges" {
  // Doubled edge 0-1 plus single edge 1-2.
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int)] = [(0, 1), (0, 1), (1, 2)]
  let result = bridges(nodes, undirected_adj(edges))
  inspect(result.length(), content="1")
  let (u, v) = result[0]
  assert_true((u == 1 && v == 2) || (u == 2 && v == 1))
}

///|
test "disconnected components are handled independently" {
  // Component A: path 0-1; component B: triangle 2-3-4.
  let nodes = [0, 1, 2, 3, 4]
  let edges : Array[(Int, Int)] = [(0, 1), (2, 3), (3, 4), (4, 2)]
  inspect(bridges(nodes, undirected_adj(edges)).length(), content="1")
  inspect(
    articulation_points(nodes, undirected_adj(edges)).length(),
    content="0",
  )
}

///|
test "deep path does not overflow (iterative DFS)" {
  let n = 5000
  let nodes : Array[Int] = []
  for i in 0..<n {
    nodes.push(i)
  }
  let neighbors = fn(u : Int) {
    let out : Array[Int] = []
    if u > 0 {
      out.push(u - 1)
    }
    if u < n - 1 {
      out.push(u + 1)
    }
    out
  }
  inspect(bridges(nodes, neighbors).length(), content="4999")
  inspect(articulation_points(nodes, neighbors).length(), content="4998")
}
