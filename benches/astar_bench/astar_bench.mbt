// benches/astar_bench — native benchmark and smoke guard for `@dir.astar`.
//
// Grid-based benchmark: 32x32 grid (≈ 1k nodes), 4-directional movement,
// Manhattan heuristic. This reproduces the "classical A* on grid" setup
// Rust pathfinding uses for its own micro-benchmarks and gives us a
// representative workload to guard against regressions.
//
// _Requirements: 14.1, 14.2_

///|
/// Smoke guard: A* from (0,0) to (31,31) on a 32x32 open grid (unit edges,
/// 4-directional), driven by an admissible Manhattan heuristic. The
/// optimal cost must equal the Manhattan distance 31 + 31 = 62 because
/// the grid has no obstacles.
test "smoke: astar on 32x32 open grid with manhattan heuristic" {
  let size = 32
  let successors = fn(pos : (Int, Int)) -> Array[((Int, Int), Int)] {
    let (x, y) = pos
    let candidates = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let out : Array[((Int, Int), Int)] = []
    for p in candidates {
      let (nx, ny) = p
      if nx >= 0 && nx < size && ny >= 0 && ny < size {
        out.push((p, 1))
      }
    }
    out
  }
  let goal = (size - 1, size - 1)
  let heuristic = fn(pos : (Int, Int)) -> Int {
    let (x, y) = pos
    let (gx, gy) = goal
    (gx - x).abs() + (gy - y).abs()
  }
  let result = @dir.astar((0, 0), successors, heuristic, fn(p) { p == goal })
  match result {
    Some((path, cost)) => {
      // Open grid ⇒ optimal cost is the Manhattan distance.
      inspect(cost, content="62")
      assert_true(path.length() == 63)
      assert_true(path[0] == (0, 0))
      assert_true(path[path.length() - 1] == goal)
    }
    None => assert_true(false)
  }
}

///|
/// Native benchmark: measure repeated A* calls over the same open-grid workload.
test "bench: astar on 32x32 open grid with manhattan heuristic" (b : @bench.T) {
  let size = 32
  let successors = fn(pos : (Int, Int)) -> Array[((Int, Int), Int)] {
    let (x, y) = pos
    let candidates = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    let out : Array[((Int, Int), Int)] = []
    for p in candidates {
      let (nx, ny) = p
      if nx >= 0 && nx < size && ny >= 0 && ny < size {
        out.push((p, 1))
      }
    }
    out
  }
  let goal = (size - 1, size - 1)
  let heuristic = fn(pos : (Int, Int)) -> Int {
    let (x, y) = pos
    let (gx, gy) = goal
    (gx - x).abs() + (gy - y).abs()
  }
  b.bench(name="astar_32x32_open_grid_manhattan", fn() {
    b.keep(@dir.astar((0, 0), successors, heuristic, fn(p) { p == goal }))
  })
}
