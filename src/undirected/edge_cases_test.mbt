// 负例/边界回归（backlog P0）：零节点、单节点、重边、不连通、非法输入。

///|
test "kruskal on empty node set yields empty forest" {
  let mst = kruskal_mst(([] : Array[Int]), ([] : Array[(Int, Int, Int)]))
  inspect(mst.length(), content="0")
}

///|
test "kruskal keeps the cheaper of duplicate parallel edges" {
  let mst = kruskal_mst([0, 1], [(0, 1, 9), (0, 1, 2), (1, 0, 5)])
  inspect(mst.length(), content="1")
  let (_, _, w) = mst[0]
  inspect(w, content="2")
}

///|
test "kruskal on disconnected graph yields a spanning forest" {
  let mst = kruskal_mst([0, 1, 2, 3], [(0, 1, 1), (2, 3, 4)])
  inspect(mst.length(), content="2")
}

///|
test "prim on empty node set yields empty forest" {
  let mst = prim_mst(([] : Array[Int]), fn(_n) { ([] : Array[(Int, Int)]) })
  inspect(mst.length(), content="0")
}

///|
test "prim on single isolated node yields empty tree" {
  let mst = prim_mst([7], fn(_n) { ([] : Array[(Int, Int)]) })
  inspect(mst.length(), content="0")
}

///|
test "prim on disconnected graph spans every component" {
  let adj : Map[Int, Array[(Int, Int)]] = Map([
    (0, [(1, 1)]),
    (1, [(0, 1)]),
    (2, [(3, 4)]),
    (3, [(2, 4)]),
  ])
  let mst = prim_mst([0, 1, 2, 3], fn(n) { adj.get(n).unwrap_or([]) })
  inspect(mst.length(), content="2")
}

///|
test "connected_components on empty node set is empty" {
  let comps = connected_components(([] : Array[Int]), fn(_n) {
    ([] : Array[Int])
  })
  inspect(comps.length(), content="0")
}

///|
test "connected_components singles out isolated nodes" {
  let comps = connected_components([0, 1, 2], fn(n) {
    if n == 0 {
      [1]
    } else if n == 1 {
      [0]
    } else {
      []
    }
  })
  inspect(comps.length(), content="2")
}

///|
test "bridges on empty and single-node graphs are empty" {
  inspect(
    bridges(([] : Array[Int]), fn(_n) { ([] : Array[Int]) }).length(),
    content="0",
  )
  inspect(bridges([5], fn(_n) { ([] : Array[Int]) }).length(), content="0")
}

///|
test "hopcroft_karp with empty sides yields empty matching" {
  let m = hopcroft_karp(([] : Array[Int]), ([] : Array[Int]), fn(_l) {
    ([] : Array[Int])
  })
  inspect(m.length(), content="0")
}

///|
test "hopcroft_karp ignores neighbours outside the right set" {
  let m = hopcroft_karp([0, 1], [10], fn(l) {
    if l == 0 {
      [10, 99]
    } else {
      [99]
    }
  })
  inspect(m.length(), content="1")
  assert_true(m[0] == (0, 10))
}

///|
test "kuhn_munkres rejects a non-square cost matrix" {
  assert_true(kuhn_munkres([[1.0, 2.0], [3.0]]) is Err(InvalidInput(_)))
}

///|
test "kuhn_munkres on empty matrix returns empty zero-cost assignment" {
  match kuhn_munkres([]) {
    Ok((a, c)) => {
      inspect(a.length(), content="0")
      inspect(c, content="0")
    }
    Err(_) => fail("空矩阵应返回空指派")
  }
}
