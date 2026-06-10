// Blackbox tests for Contraction Hierarchies (ch.mbt).

///|
test "ch_query matches dijkstra on 5-node weighted graph" {
  // Small backbone: 0 -(1)-> 1 -(2)-> 2 -(3)-> 3 -(4)-> 4
  //                 0 -(100)-> 4  (shortcut alternative, much more expensive)
  let nodes = [0, 1, 2, 3, 4]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (1, 2, 2),
    (2, 3, 3),
    (3, 4, 4),
    (0, 4, 100),
  ]
  let adj : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let succ = fn(n : Int) { adj[n] }
  let graph = ch_preprocess(nodes, succ)
  // Compare CH cost to plain Dijkstra cost for source = 0.
  for v in nodes {
    let ch_r = ch_query(graph, 0, v)
    let dj_r = @dir.dijkstra(0, succ, fn(n) { n == v })
    match (ch_r, dj_r) {
      (Some((_, ch_cost)), Some((_, dj_cost))) =>
        assert_true(ch_cost == dj_cost)
      (None, None) => assert_true(true)
      (None, Some(_)) => assert_true(false)
      (Some(_), None) => assert_true(false)
    }
  }
}

///|
test "ch_query source equals target returns zero cost" {
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 5), (1, 2, 5)]
  let adj : Array[Array[(Int, Int)]] = [[], [], []]
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let graph = ch_preprocess(nodes, fn(n) { adj[n] })
  match ch_query(graph, 0, 0) {
    Some((path, cost)) => {
      inspect(path, content="[0]")
      inspect(cost, content="0")
    }
    None => assert_true(false)
  }
}

///|
test "ch_query returns None when target unreachable" {
  // Two disconnected components: {0, 1} and {2}.
  let nodes = [0, 1, 2]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 1)]
  let adj : Array[Array[(Int, Int)]] = [[], [], []]
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let graph = ch_preprocess(nodes, fn(n) { adj[n] })
  match ch_query(graph, 0, 2) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
}

///|
test "ch_query expanded path matches dijkstra node-for-node" {
  // 6-node graph: 0->1->2->3->4->5 with a shortcut inducement
  //   0 -(1)-> 1 -(1)-> 2 -(1)-> 3 -(1)-> 4 -(1)-> 5
  // Correct path: [0, 1, 2, 3, 4, 5], cost 5. This test verifies that
  // ch_query's path-expansion (via recursive shortcut unfolding) gives
  // back every original node, matching Dijkstra's output exactly.
  let nodes = [0, 1, 2, 3, 4, 5]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 1),
    (1, 2, 1),
    (2, 3, 1),
    (3, 4, 1),
    (4, 5, 1),
  ]
  let adj : Array[Array[(Int, Int)]] = [[], [], [], [], [], []]
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let succ = fn(n : Int) { adj[n] }
  let graph = ch_preprocess(nodes, succ)
  let ch_r = ch_query(graph, 0, 5)
  let dj_r = @dir.dijkstra(0, succ, fn(n) { n == 5 })
  match (ch_r, dj_r) {
    (Some((ch_path, ch_cost)), Some((dj_path, dj_cost))) => {
      // Cost agreement is strict.
      assert_true(ch_cost == dj_cost)
      // Path agreement: CH must now return the fully expanded original path,
      // not just [source, target]. Because this graph has a single simple
      // path from 0 to 5, both algorithms must return exactly the same
      // sequence of 6 nodes.
      assert_true(ch_path.length() == dj_path.length())
      let mut i = 0
      while i < ch_path.length() {
        assert_true(ch_path[i] == dj_path[i])
        i += 1
      }
    }
    _ => assert_true(false)
  }
}

///|
test "ch_query expanded path visits every intermediate node" {
  // 4-node chain: 0 -(2)-> 1 -(2)-> 2 -(2)-> 3. CH must visit 1 and 2.
  let nodes = [0, 1, 2, 3]
  let edges : Array[(Int, Int, Int)] = [(0, 1, 2), (1, 2, 2), (2, 3, 2)]
  let adj : Array[Array[(Int, Int)]] = [[], [], [], []]
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let graph = ch_preprocess(nodes, fn(n) { adj[n] })
  match ch_query(graph, 0, 3) {
    Some((path, cost)) => {
      inspect(path.length(), content="4") // 0, 1, 2, 3 all present
      inspect(cost, content="6")
      inspect(path[0], content="0")
      inspect(path[3], content="3")
    }
    None => assert_true(false)
  }
}
