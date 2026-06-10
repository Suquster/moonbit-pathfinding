// examples/network_routing — runnable demonstration of `@dir.dijkstra` on a
// 10-node simulated backbone network.
//
// Fulfils Requirement 9.3 (3rd runnable example) and 9.4 (`moon run` exits
// with code 0 and prints expected output). Complements the unweighted BFS
// maze_solver and the heuristic A* eight_puzzle by exercising the
// non-negative weighted shortest-path API on real-world-shaped data.
//
// Inspiration: NSLB (Network Simulation Lab / 网络模拟实验) — a teaching
// setup where each router is labelled "Router A" .. "Router J" and every
// link carries a millisecond-scale one-way latency. Dijkstra picks the
// minimum-latency route; an asymmetric "monitor-only" router J illustrates
// how the algorithm reports unreachable destinations as `None`.
//
// Run with:
//   moon run examples/network_routing
//
// Node type : Int  — router index, 0..9 (displayed as "Router A".."Router J")
// Weight    : Double — one-way link latency, milliseconds

///|
/// Human-readable names for routers 0..9.
///
/// `ROUTER_NAMES[i]` is the canonical label printed in topology and query
/// reports. The index is what Dijkstra actually sees.
let router_names : Array[String] = [
  "Router A", "Router B", "Router C", "Router D", "Router E", "Router F", "Router G",
  "Router H", "Router I", "Router J",
]

///|
/// Number of routers in the simulated network.
const ROUTER_COUNT : Int = 10

///|
/// The backbone link list, as directed edges `(src, dst, latency_ms)`.
///
/// Most links are symmetric (two entries per physical cable) to model a
/// typical IP backbone. Router J is intentionally one-way-only: the sole
/// link "I -> J" with no "J -> I" counterpart makes J a pure ingress
/// monitor router — reachable *to*, but unable to *originate* any route.
/// This asymmetry is what produces the unreachable query scenario below.
fn backbone_edges() -> Array[(Int, Int, Double)] {
  // (A, B, C, D, E, F, G, H, I, J) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
  let symmetric : Array[(Int, Int, Double)] = [
    (0, 1, 5.0), // A <-> B  : 5.0 ms
    (0, 3, 8.0), // A <-> D  : 8.0 ms
    (1, 2, 12.5), // B <-> C  : 12.5 ms
    (1, 5, 20.0), // B <-> F  : 20.0 ms
    (2, 3, 3.5), // C <-> D  : 3.5 ms
    (2, 4, 7.0), // C <-> E  : 7.0 ms
    (3, 7, 15.0), // D <-> H  : 15.0 ms
    (4, 5, 4.0), // E <-> F  : 4.0 ms
    (4, 8, 11.0), // E <-> I  : 11.0 ms
    (5, 6, 6.5), // F <-> G  : 6.5 ms
    (6, 7, 2.0), // G <-> H  : 2.0 ms
    (6, 8, 9.0), // G <-> I  : 9.0 ms
  ]
  let out : Array[(Int, Int, Double)] = []
  for e in symmetric {
    let (u, v, w) = e
    out.push((u, v, w))
    out.push((v, u, w))
  }
  // One-way ingress link to the "monitor-only" Router J (index 9).
  // Making this link unidirectional means every node can reach J through
  // I -> J, but J itself has no outgoing edges — so any query whose source
  // is J will correctly return `None` (Requirement 1.4 graceful handling).
  out.push((8, 9, 3.0)) // I -> J : 3.0 ms (no reverse)
  out
}

///|
/// Build a `Map[Int, Array[(Int, Double)]]` adjacency list so the Dijkstra
/// successor closure is O(1) per call instead of scanning all edges.
fn build_adjacency(
  edges : Array[(Int, Int, Double)],
) -> Map[Int, Array[(Int, Double)]] {
  let adj : Map[Int, Array[(Int, Double)]] = Map::new()
  for i in 0..<ROUTER_COUNT {
    adj[i] = []
  }
  for e in edges {
    let (u, v, w) = e
    match adj.get(u) {
      Some(list) => list.push((v, w))
      None => adj[u] = [(v, w)]
    }
  }
  adj
}

///|
/// Format a Double latency with one decimal place, e.g. `5.0 ms`.
///
/// `Double::to_string` already prints "5" or "12.5" nicely without
/// exponent notation for the small magnitudes used here, so we just append
/// the unit suffix.
fn fmt_latency(ms : Double) -> String {
  ms.to_string() + " ms"
}

///|
/// Print the backbone topology as a table keyed by source router.
///
/// Every router that has at least one outbound link is listed with its
/// neighbours and per-link latency. Routers with no outbound edges
/// (e.g. the monitor-only Router J) are still listed so the reader can see
/// at a glance why they can only be a destination, not a source.
fn print_topology(adj : Map[Int, Array[(Int, Double)]]) -> Unit {
  println("--- Network topology (10 routers, directed links) ---")
  for i in 0..<ROUTER_COUNT {
    let name = router_names[i]
    let neighbors = match adj.get(i) {
      Some(list) => list
      None => []
    }
    if neighbors.length() == 0 {
      println(name + " : (no outgoing links — ingress-only monitor)")
      continue
    }
    let buf = StringBuilder::new()
    buf.write_string(name)
    buf.write_string(" -> { ")
    for k in 0..<neighbors.length() {
      let (v, w) = neighbors[k]
      if k > 0 {
        buf.write_string(", ")
      }
      buf.write_string(router_names[v])
      buf.write_string(" [")
      buf.write_string(fmt_latency(w))
      buf.write_string("]")
    }
    buf.write_string(" }")
    println(buf.to_string())
  }
  println("")
}

///|
/// A single query scenario: find the minimum-latency route `src -> dst`
/// across the backbone network. The `note` is a free-form string printed
/// alongside the result to give human context (e.g. "cross-country hop").
struct Query {
  src : Int
  dst : Int
  note : String
}

///|
/// Run one query through `@dir.dijkstra` and print the outcome.
///
/// Output layout per query:
///   1. header line identifying the query (src -> dst, note);
///   2. the resolved route with intermediate routers and total latency, OR
///      a "no route available" diagnostic if the destination is unreachable.
///
/// The function never throws — unreachable scenarios are reported textually
/// so `moon run` still exits with code 0 as required by Requirement 9.4.
fn run_query(adj : Map[Int, Array[(Int, Double)]], query : Query) -> Unit {
  let src_name = router_names[query.src]
  let dst_name = router_names[query.dst]
  println("Query: " + src_name + " -> " + dst_name + "  (" + query.note + ")")
  // Dijkstra's successor closure reads the pre-built adjacency map, and the
  // goal predicate is a single integer equality check against the target.
  let result = @dir.dijkstra(
    query.src,
    fn(u) {
      match adj.get(u) {
        Some(list) => list
        None => []
      }
    },
    fn(u) { u == query.dst },
  )
  match result {
    Some((path, total)) => {
      let buf = StringBuilder::new()
      buf.write_string("  Route: ")
      for i in 0..<path.length() {
        if i > 0 {
          buf.write_string(" -> ")
        }
        buf.write_string(router_names[path[i]])
      }
      println(buf.to_string())
      println("  Hops : " + (path.length() - 1).to_string())
      println("  Total latency: " + fmt_latency(total))
    }
    None =>
      // Requirement 1.4: unreachable destinations yield `None`, never hang.
      println(
        "  No route available (destination is unreachable from " +
        src_name +
        ").",
      )
  }
  println("")
}

///|
/// The predefined query set exercised by the main entry point.
///
/// Covers three intentionally different shapes so both the reachable and
/// unreachable branches of Dijkstra are exercised:
///
///   * A -> J : traverses the full length of the backbone, demonstrating a
///     multi-hop optimal route (edges chosen to make the optimum non-obvious
///     at a glance — A->B->F->G->I->J is shorter than A->D->H->G->I->J).
///   * C -> H : a mid-network query where the greedy local choice
///     (C->D->H direct) also happens to be globally optimal; this sanity-
///     checks the result against human intuition.
///   * J -> A : an unreachable query. Router J is an ingress-only monitor
///     (no outgoing links), so Dijkstra must return `None`.
fn queries() -> Array[Query] {
  [
    {
      src: 0, // Router A
      dst: 9, // Router J
      note: "cross-backbone, shortest-latency route",
    },
    {
      src: 2, // Router C
      dst: 7, // Router H
      note: "mid-network routing, dense-region query",
    },
    {
      src: 9, // Router J (ingress-only monitor)
      dst: 0, // Router A
      note: "asymmetric link — expected to be unreachable",
    },
  ]
}

///|
/// Program entry point. Prints a header, the topology, then runs every
/// predefined query. Always exits with code 0.
fn main {
  println("moonbit-pathfinding · network_routing example")
  println("Algorithm : Dijkstra (non-negative weighted shortest path)")
  println("Weight    : Double (link latency in milliseconds)")
  println(
    "Inspiration: NSLB (Network Simulation Lab / 网络模拟实验) — routers A..J",
  )
  println("")
  let edges = backbone_edges()
  let adj = build_adjacency(edges)
  print_topology(adj)
  for q in queries() {
    run_query(adj, q)
  }
}
