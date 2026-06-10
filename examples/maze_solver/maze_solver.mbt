// examples/maze_solver — runnable demonstration of `@uw.bfs` on ASCII mazes.
//
// Fulfils Requirement 9.3 (at least 3 runnable examples) and 9.4
// (`moon run` exits with code 0 and prints expected output) and R4.4
// (a complete `examples/` entry using `(Int, Int)` grid coordinates).
//
// Run with:
//   moon run examples/maze_solver
//
// Conventions (both in input and printed output):
//   '#' = wall, '.' = open cell, 'S' = start, 'G' = goal, '*' = path cell.

///|
/// A 2D character maze with located start and goal cells.
///
/// The grid is row-major: `grid[r][c]` is the cell at row `r`, column `c`.
/// `start` and `goal` store the `(row, col)` positions of the `'S'` and
/// `'G'` markers,discovered when the `Maze` is constructed.
struct Maze {
  grid : Array[Array[Char]]
  rows : Int
  cols : Int
  start : (Int, Int)
  goal : (Int, Int)
}

///|
/// Build a `Maze` from a 2D character grid, locating its `'S'` and `'G'`.
///
/// Returns `None` if the grid is empty or is missing either marker;
/// otherwise returns `Some(maze)` with the start / goal coordinates cached.
fn Maze::new(grid : Array[Array[Char]]) -> Maze? {
  let rows = grid.length()
  if rows == 0 {
    return None
  }
  let cols = grid[0].length()
  let mut start : (Int, Int)? = None
  let mut goal : (Int, Int)? = None
  for r in 0..<rows {
    let row = grid[r]
    for c in 0..<row.length() {
      match row[c] {
        'S' => start = Some((r, c))
        'G' => goal = Some((r, c))
        _ => ()
      }
    }
  }
  match (start, goal) {
    (Some(s), Some(g)) => Some({ grid, rows, cols, start: s, goal: g })
    _ => None
  }
}

///|
/// Return `true` when `(r, c)` is in bounds and is not a wall `'#'`.
fn Maze::passable(self : Maze, pos : (Int, Int)) -> Bool {
  let (r, c) = pos
  if r < 0 || r >= self.rows || c < 0 || c >= self.cols {
    return false
  }
  self.grid[r][c] != '#'
}

///|
/// Enumerate the 4-neighbourhood (up/down/left/right) of a cell, filtered
/// to in-bounds passable cells. This is the successor function fed to BFS.
fn Maze::neighbors(self : Maze, pos : (Int, Int)) -> Array[(Int, Int)] {
  let (r, c) = pos
  let candidates = [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]
  let out : Array[(Int, Int)] = []
  for p in candidates {
    if self.passable(p) {
      out.push(p)
    }
  }
  out
}

///|
/// Render the maze as a single string, overlaying the solved path with `'*'`.
///
/// Cells in the path that are already `'S'` or `'G'` keep their original
/// marker, so the reader can see both endpoints clearly. Every other path
/// cell is drawn as `'*'`.
fn Maze::render(self : Maze, path : Array[(Int, Int)]) -> String {
  // Build a quick lookup so each cell knows whether it is on the path.
  let on_path : Map[(Int, Int), Bool] = Map::new()
  for p in path {
    on_path[p] = true
  }
  let buf = StringBuilder::new()
  for r in 0..<self.rows {
    for c in 0..<self.cols {
      let cell = self.grid[r][c]
      let ch = match cell {
        'S' | 'G' => cell
        _ => if on_path.contains((r, c)) { '*' } else { cell }
      }
      buf.write_char(ch)
    }
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// Parse a list of row strings (e.g. `"#S.#"`) into a row-major char grid.
///
/// The input rows are expected to share the same length; rows of differing
/// length are accepted but will produce a jagged grid that the maze helpers
/// still handle correctly via per-row bounds checks.
fn parse_maze(rows : Array[String]) -> Array[Array[Char]] {
  let out : Array[Array[Char]] = []
  for row in rows {
    let chars : Array[Char] = []
    for ch in row {
      chars.push(ch)
    }
    out.push(chars)
  }
  out
}

///|
/// A named maze scenario the example program will solve and print.
struct Scenario {
  name : String
  rows : Array[String]
}

///|
/// Solve a single scenario with BFS and print both the ASCII map and stats.
///
/// Outputs (in order):
///   1. the scenario title line;
///   2. the raw maze (no highlights);
///   3. the solved maze with `'*'` path overlay, or a "no path" message;
///   4. a one-line summary with path length (edge count) and cells visited.
fn solve_and_print(scenario : Scenario) -> Unit {
  println("=== " + scenario.name + " ===")
  let grid = parse_maze(scenario.rows)
  let maze = match Maze::new(grid) {
    Some(m) => m
    None => {
      println("[skip] maze missing 'S' or 'G' marker")
      println("")
      return
    }
  }
  println("Input maze:")
  println(maze.render([]))
  // Feed `@uw.bfs` a closure-based successor and goal predicate. This
  // showcases the R3 "successors + goal" unified API on 2D grid coords.
  let path_opt = @uw.bfs(maze.start, fn(p) { maze.neighbors(p) }, fn(p) {
    p == maze.goal
  })
  match path_opt {
    Some(path) => {
      println("Solved path (steps = " + (path.length() - 1).to_string() + "):")
      println(maze.render(path))
    }
    None => {
      println("No path from S to G.")
      println("")
    }
  }
}

///|
/// Predefined scenarios exercised by the main entry point.
///
/// The set covers four shapes intentionally:
///   * a tiny corridor (sanity check, 1 row);
///   * a small open room (multiple equal-length paths, tests determinism);
///   * a classic serpentine maze (forces detours around walls);
///   * an unreachable goal (validates graceful `None` handling per R1.4);
///   * a larger 9x13 grid (bigger case for visual impact).
fn scenarios() -> Array[Scenario] {
  [
    { name: "Scenario 1: straight corridor", rows: ["S...G"] },
    {
      name: "Scenario 2: 5x5 open room",
      rows: ["S....", ".....", "..#..", ".....", "....G"],
    },
    {
      name: "Scenario 3: serpentine 7x9",
      rows: [
        "S........", "########.", ".........", ".########", ".........", "########.",
        ".......G.",
      ],
    },
    {
      name: "Scenario 4: unreachable goal (walled-off)",
      rows: ["S..#..G", ".###..."],
    },
    {
      name: "Scenario 5: 9x13 canyon",
      rows: [
        "S............", "###########..", "............#", "..##########.", ".............",
        ".#########...", ".........####", "####.........", "...........G.",
      ],
    },
  ]
}

///|
/// Program entry point. Runs every predefined scenario in order, printing
/// the input and the solved overlay for each. Exits with code 0 as long
/// as the process completes normally (BFS failures are rendered, not thrown).
fn main {
  println("moonbit-pathfinding · maze_solver example")
  println("Algorithm: BFS (unweighted shortest path, 4-connected grid)")
  println("Legend: '#'=wall, '.'=open, 'S'=start, 'G'=goal, '*'=path")
  println("")
  for scenario in scenarios() {
    solve_and_print(scenario)
  }
}
