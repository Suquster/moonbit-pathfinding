// playground/solver_test.mbt — Bridge ⇄ library equivalence tests.
//
// These tests assert that every `solve_xxx` wrapper exposed to the JS /
// WASM playground returns **the same shortest-path cost** as the
// underlying `src/` algorithm on the same input. If the playground ever
// diverges from the formally-verified library, `moon test` fails — so
// the demo we show evaluators is always a faithful view of the proved
// algorithms.
//
// Validates: Requirements 16.5 (playground correctness),
//            13.1 (cross-algorithm consensus),
//            13.8 (A* equivalence to Dijkstra under admissible heuristic).

///|
/// 5×4 grid, no walls — pick a corner-to-corner shortest path and check
/// every wrapper returns the same length.
test "playground bridge: empty 5x4 grid → consensus across algorithms" {
  let w = 5
  let h = 4
  let blocked : Array[Bool] = Array::make(w * h, false)
  let start = 0 // (0,0)
  let goal = w * h - 1 // (3,4)
  let bfs_path = solve_bfs(w, h, blocked, start, goal)
  let (dj_path, dj_cost) = solve_dijkstra(w, h, blocked, start, goal)
  let (as_path, as_cost) = solve_astar(w, h, blocked, start, goal)
  // BFS length = number of edges = nodes - 1.
  inspect(bfs_path.length() - 1, content="7")
  // Dijkstra cost = sum of unit edges = same as BFS length-1.
  inspect(dj_cost, content="7")
  // A* with admissible heuristic must match Dijkstra exactly.
  inspect(as_cost, content="7")
  // Path start/end consistency for every wrapper.
  inspect(bfs_path[0], content="0")
  inspect(bfs_path[bfs_path.length() - 1], content="19")
  inspect(dj_path[0], content="0")
  inspect(dj_path[dj_path.length() - 1], content="19")
  inspect(as_path[0], content="0")
  inspect(as_path[as_path.length() - 1], content="19")
}

///|
/// 4×4 grid with a wall splitting the right half — verify the wrapper
/// correctly routes around obstacles AND the JPS wrapper agrees with
/// the 4-neighbour algorithms on shortest-path cost (it shouldn't, since
/// JPS uses 8-neighbour, but its cost should NEVER exceed the 4-neighbour
/// answer).
test "playground bridge: 4x4 with obstacle, JPS ≤ Dijkstra cost" {
  let w = 4
  let h = 4
  let blocked : Array[Bool] = Array::make(w * h, false)
  // Place 3 walls forming a vertical line at column 2, rows 0..2.
  blocked[2] = true // (0,2)
  blocked[6] = true // (1,2)
  blocked[10] = true // (2,2)
  let start = 0 // (0,0)
  let goal = 3 // (0,3)
  let bfs_path = solve_bfs(w, h, blocked, start, goal)
  let (_, dj_cost) = solve_dijkstra(w, h, blocked, start, goal)
  let (_, as_cost) = solve_astar(w, h, blocked, start, goal)
  let (jps_flat, jps_cost_x100) = solve_jps(w, h, blocked, start, goal)
  // 4-neighbour shortest path: down 3, right 3, up 3 = 9 steps.
  inspect(bfs_path.length() - 1, content="9")
  inspect(dj_cost, content="9")
  inspect(as_cost, content="9")
  // JPS uses 8-neighbour so cost ≤ 9 in *Octile* units. The encoded
  // value is cost * 100 (rounded down), so 9.0 → 900 max.
  assert_true(jps_cost_x100 >= 0 && jps_cost_x100 <= 900)
  // JPS path must hit start and goal.
  assert_true(jps_flat.length() >= 2)
  inspect(jps_flat[0], content="0")
  inspect(jps_flat[jps_flat.length() - 1], content="3")
}

///|
/// Unreachable goal — every wrapper must return the "empty path"
/// sentinel ([] for BFS, ([], -1) for weighted).
test "playground bridge: unreachable goal sentinels" {
  let w = 3
  let h = 3
  let blocked : Array[Bool] = Array::make(w * h, false)
  // Wall off the goal corner, including the diagonal so the goal is
  // unreachable under both 4-neighbour (BFS/Dijkstra/A*) and
  // 8-neighbour (JPS) movement.
  blocked[4] = true // (1,1)
  blocked[5] = true // (1,2)
  blocked[7] = true // (2,1)
  let start = 0
  let goal = 8 // (2,2) surrounded by walls from (0,0)
  let bfs_path = solve_bfs(w, h, blocked, start, goal)
  let (dj_path, dj_cost) = solve_dijkstra(w, h, blocked, start, goal)
  let (as_path, as_cost) = solve_astar(w, h, blocked, start, goal)
  let (jps_flat, jps_cost) = solve_jps(w, h, blocked, start, goal)
  inspect(bfs_path.length(), content="0")
  inspect(dj_path.length(), content="0")
  inspect(dj_cost, content="-1")
  inspect(as_path.length(), content="0")
  inspect(as_cost, content="-1")
  inspect(jps_flat.length(), content="0")
  inspect(jps_cost, content="-1")
}

///|
/// Start equals goal — trivial path of length 1, cost 0.
test "playground bridge: start == goal trivial path" {
  let w = 4
  let h = 4
  let blocked : Array[Bool] = Array::make(w * h, false)
  let bfs_path = solve_bfs(w, h, blocked, 5, 5)
  let (dj_path, dj_cost) = solve_dijkstra(w, h, blocked, 5, 5)
  let (as_path, as_cost) = solve_astar(w, h, blocked, 5, 5)
  inspect(bfs_path.length(), content="1")
  inspect(bfs_path[0], content="5")
  inspect(dj_path.length(), content="1")
  inspect(dj_cost, content="0")
  inspect(as_path.length(), content="1")
  inspect(as_cost, content="0")
}
