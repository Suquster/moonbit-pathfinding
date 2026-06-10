// playground/solver.mbt — Bridge between the algorithm library and the
// browser playground.
//
// **Design philosophy** (tasks.md 38.x / R16):
//
// The browser-side visualiser (`app.js`) needs three things from every
// algorithm:
//   1. The final shortest path (cell list)
//   2. The total cost (Int or Double, depends on algorithm)
//   3. The expansion order (which cells were visited, in what order) so
//      we can animate the frontier as it sweeps across the grid.
//
// Items (1) and (2) come straight from the formally-verified `src/`
// library — we just wrap each algorithm with a grid-friendly signature
// (width, height, blocked-mask, start coords, goal coords) and call out
// to `@uw.bfs`, `@dir.dijkstra`, `@dir.astar`, `@adv.jps`.
//
// Item (3) needs a parallel implementation that records expansion order
// step-by-step — `src/` algorithms intentionally don't expose that hook
// (it would pollute the API and slow them down for production use).
// We re-derive the expansion in `app.js` (pure JS); the MoonBit wrappers
// here exist only to provide the **trustworthy** path + cost answer that
// every animation step is validated against.
//
// The companion `solver_test.mbt` exercises every wrapper on the same
// input the browser uses, asserting that
//   wrapper output ≡ library output
// so that "what the playground shows" and "what `moon prove` proved"
// are demonstrably the same thing.
//
// All wrappers are `pub` so they can be exported under MoonBit's JS /
// wasm-gc backends; v1.0.0 ships the library + tests, the actual export
// step happens via `moon build --target {wasm-gc|js} -p playground` and
// `scripts/build_playground.ps1`.

///|
/// Convert a flat row-major blocked mask + grid dimensions into the
/// successor function our `@uw.bfs` and `@dir.dijkstra` API expects.
///
/// A 4-neighbour grid (up/down/left/right). Walls and out-of-bounds
/// cells are pruned. Cell `(r, c)` is encoded as `r * width + c`.
fn grid_4n_succ(
  width : Int,
  height : Int,
  blocked : Array[Bool],
) -> (Int) -> Array[Int] {
  fn(n : Int) -> Array[Int] {
    let r = n / width
    let c = n % width
    let out : Array[Int] = []
    let neigh = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    for d in neigh {
      let (dr, dc) = d
      let nr = r + dr
      let nc = c + dc
      if nr < 0 || nr >= height || nc < 0 || nc >= width {
        continue
      }
      let idx = nr * width + nc
      if blocked[idx] {
        continue
      }
      out.push(idx)
    }
    out
  }
}

///|
/// Same as `grid_4n_succ` but emits `(neighbour, 1)` pairs for the
/// weighted-API algorithms (Dijkstra / A*).
fn grid_4n_succ_w(
  width : Int,
  height : Int,
  blocked : Array[Bool],
) -> (Int) -> Array[(Int, Int)] {
  fn(n : Int) -> Array[(Int, Int)] {
    let r = n / width
    let c = n % width
    let out : Array[(Int, Int)] = []
    let neigh = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    for d in neigh {
      let (dr, dc) = d
      let nr = r + dr
      let nc = c + dc
      if nr < 0 || nr >= height || nc < 0 || nc >= width {
        continue
      }
      let idx = nr * width + nc
      if blocked[idx] {
        continue
      }
      out.push((idx, 1))
    }
    out
  }
}

///|
/// Manhattan distance heuristic for grid A*.
fn manhattan_h(width : Int, goal : Int) -> (Int) -> Int {
  let gr = goal / width
  let gc = goal % width
  fn(n : Int) -> Int {
    let r = n / width
    let c = n % width
    (r - gr).abs() + (c - gc).abs()
  }
}

///|
/// Solve a 4-neighbour grid with **BFS** and return the path as a flat
/// `Array[Int]` of cell indices.
///
/// `width × height` describes the grid; `blocked[i]` is `true` if cell
/// `i` is a wall. `start` and `goal` are flat cell indices.
///
/// Returns `[]` when no path exists; this convention keeps the JS bridge
/// simple (a non-empty array always means "path found").
pub fn solve_bfs(
  width : Int,
  height : Int,
  blocked : Array[Bool],
  start : Int,
  goal : Int,
) -> Array[Int] {
  let succ = grid_4n_succ(width, height, blocked)
  match @uw.bfs(start, succ, fn(n) { n == goal }) {
    Some(path) => path
    None => []
  }
}

///|
/// Solve a 4-neighbour grid with **Dijkstra** and return `(path, cost)`.
/// `cost` is the number of steps (since edges are unit-weight).
///
/// When unreachable, returns `([], -1)` so the JS bridge can distinguish
/// "no path" from "0-cost trivial path".
pub fn solve_dijkstra(
  width : Int,
  height : Int,
  blocked : Array[Bool],
  start : Int,
  goal : Int,
) -> (Array[Int], Int) {
  let succ = grid_4n_succ_w(width, height, blocked)
  match @dir.dijkstra(start, succ, fn(n) { n == goal }) {
    Some((path, cost)) => (path, cost)
    None => ([], -1)
  }
}

///|
/// Solve a 4-neighbour grid with **A\*** (Manhattan heuristic) and
/// return `(path, cost)`.
///
/// Heuristic admissibility on a 4-neighbour unit-cost grid is a textbook
/// result; this wrapper therefore returns Dijkstra-equivalent costs.
pub fn solve_astar(
  width : Int,
  height : Int,
  blocked : Array[Bool],
  start : Int,
  goal : Int,
) -> (Array[Int], Int) {
  let succ = grid_4n_succ_w(width, height, blocked)
  let h = manhattan_h(width, goal)
  match @dir.astar(start, succ, h, fn(n) { n == goal }) {
    Some((path, cost)) => (path, cost)
    None => ([], -1)
  }
}

///|
/// Solve a 4-neighbour grid with **JPS** and return `(path, cost)` as
/// jump-point coordinates flattened to `Array[Int]`.
///
/// JPS is an 8-neighbour algorithm but our visualiser only animates
/// 4-neighbour moves; we expose JPS here using the `JPSGrid` directly
/// (which is fundamentally 8-neighbour) and let the front-end interpolate
/// the straight runs between jump-points for the animation.
///
/// `cost` is **rounded down** to `Int` (multiplied by 100 first to keep
/// 2 decimals of precision) so the JS side can render it without
/// double-precision marshalling.
pub fn solve_jps(
  width : Int,
  height : Int,
  blocked : Array[Bool],
  start : Int,
  goal : Int,
) -> (Array[Int], Int) {
  match @adv.JPSGrid::new(width, height, blocked) {
    None => ([], -1)
    Some(grid) => {
      let sr = start / width
      let sc = start % width
      let gr = goal / width
      let gc = goal % width
      match @adv.jps(grid, (sr, sc), (gr, gc)) {
        Some((pts, cost)) => {
          let flat : Array[Int] = []
          for p in pts {
            let (r, c) = p
            flat.push(r * width + c)
          }
          (flat, (cost * 100.0).to_int())
        }
        None => ([], -1)
      }
    }
  }
}
