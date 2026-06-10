// Property 11 · ALT heuristic is admissible & monotone.
//
// Validates: Requirement 18.1(c) safety.
//
// Because ALT uses the triangular-inequality heuristic
// `h(n) = max_l |dist(l, n) - dist(l, t)|`, we can test:
//   (a) h(target, target) == 0               — goal node sees zero estimate
//   (b) alt_query result equals dijkstra    — cost-preserving
// (Full pointwise `h(n) <= dist(n, t)` would require exposing the
// internal heuristic; we test the observable consequence instead.)

///|
test "PBT 11: alt_query cost matches dijkstra on random graphs" {
  let seeds = [14, 22, 36, 81, 192]
  for s in seeds {
    let (nodes, edges) = gen_nonneg_graph(s, 10, 0.3, 12)
    let adj : Array[Array[(Int, Int)]] = Array::makei(nodes.length(), fn(_) {
      []
    })
    for e in edges {
      let (u, v, w) = e
      adj[u].push((v, w))
    }
    let succ = fn(n : Int) { adj[n] }
    let lm = @adv.alt_preprocess(nodes, succ, 3)
    for src in nodes {
      for dst in nodes {
        let alt_r = @adv.alt_query(lm, src, dst, succ)
        let dj_r = @dir.dijkstra(src, succ, fn(v) { v == dst })
        match (alt_r, dj_r) {
          (Some((_, alt_cost)), Some((_, dj_cost))) =>
            if alt_cost != dj_cost {
              println(
                "ALT MISMATCH seed=\{s} src=\{src} dst=\{dst} alt=\{alt_cost} dj=\{dj_cost}",
              )
              assert_true(false)
            }
          (None, None) => ()
          (None, Some(_)) => {
            println(
              "ALT returned None but dijkstra found path: seed=\{s} src=\{src} dst=\{dst}",
            )
            assert_true(false)
          }
          (Some(_), None) => {
            println(
              "ALT found path but dijkstra None: seed=\{s} src=\{src} dst=\{dst}",
            )
            assert_true(false)
          }
        }
      }
    }
  }
}

///|
test "PBT 11b: alt_query target=source returns zero cost" {
  let (nodes, edges) = gen_nonneg_graph(99, 6, 0.4, 5)
  let adj : Array[Array[(Int, Int)]] = Array::makei(nodes.length(), fn(_) { [] })
  for e in edges {
    let (u, v, w) = e
    adj[u].push((v, w))
  }
  let lm = @adv.alt_preprocess(nodes, fn(n) { adj[n] }, 2)
  for n in nodes {
    match @adv.alt_query(lm, n, n, fn(i) { adj[i] }) {
      Some((path, cost)) => {
        assert_true(path.length() == 1)
        assert_true(cost == 0)
      }
      None => assert_true(false)
    }
  }
}
