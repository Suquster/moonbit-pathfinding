// Blackbox tests for ALT.

///|
test "alt_query result matches dijkstra on 5-node graph" {
  // Small backbone: 0 -(2)-> 1 -(1)-> 2 -(3)-> 3 -(1)-> 4
  //                 0 -(5)-> 2 (shortcut)
  let nodes = [0, 1, 2, 3, 4]
  let edges : Array[(Int, Int, Int)] = [
    (0, 1, 2),
    (0, 2, 5),
    (1, 2, 1),
    (2, 3, 3),
    (3, 4, 1),
  ]
  let adj : Array[Array[(Int, Int)]] = [[], [], [], [], []]
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let succ = fn(n : Int) { adj[n] }
  let lm = alt_preprocess(nodes, succ, 2)
  // Every (source, target) pair must agree with Dijkstra on cost.
  for s in nodes {
    for t in nodes {
      let alt_r = alt_query(lm, s, t, succ)
      let dj_r = @dir.dijkstra(s, succ, fn(n) { n == t })
      match (alt_r, dj_r) {
        (Some((_, alt_cost)), Some((_, dj_cost))) =>
          assert_true(alt_cost == dj_cost)
        (None, None) => assert_true(true)
        _ => assert_true(false)
      }
    }
  }
}

///|
test "alt_query source equals target returns zero cost" {
  let nodes = [0, 1]
  let adj : Array[Array[(Int, Int)]] = [[(1, 3)], []]
  let lm = alt_preprocess(nodes, fn(n) { adj[n] }, 1)
  match alt_query(lm, 0, 0, fn(n) { adj[n] }) {
    Some((path, cost)) => {
      inspect(path, content="[0]")
      inspect(cost, content="0")
    }
    None => assert_true(false)
  }
}

///|
test "alt_query returns None when unreachable" {
  let nodes = [0, 1, 2]
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [], []]
  let lm = alt_preprocess(nodes, fn(n) { adj[n] }, 1)
  match alt_query(lm, 0, 2, fn(n) { adj[n] }) {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
}
