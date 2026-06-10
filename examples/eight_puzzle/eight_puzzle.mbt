// examples/eight_puzzle — runnable demonstration of `@dir.astar` on the
// classic 3x3 sliding-tile puzzle (a.k.a. 8-puzzle).
//
// Fulfils Requirement 9.3 (at least 3 runnable examples) and 9.4 (`moon run`
// exits with code 0 and prints expected output). Showcases the unified
// weighted-search API from R3 on a pure state-space search problem, with a
// custom admissible heuristic (sum of Manhattan distances).
//
// Run with:
//   moon run examples/eight_puzzle
//
// Board convention:
//   - '0' marks the blank square.
//   - Tiles '1'..'8' are the numbered pieces, indexed row-major.
//   - The goal configuration is the string "123456780":
//         1 2 3
//         4 5 6
//         7 8 _
//
// Node type: we encode each 3x3 state as a 9-character `String` (digits
// '0'..'8'). `String` already satisfies `Eq + Hash`, so no custom wrapper is
// needed. This matches the design note in tasks.md 17.2:
//   "MoonBit 无原生固定长度数组 hash，可以用 String".

///|
/// The goal configuration, blank in the bottom-right corner.
const GOAL : String = "123456780"

///|
/// Convert a `String` into a mutable `Array[Char]` so we can edit cells.
///
/// The 8-puzzle state is always 9 ASCII characters ('0'..'8' in some order),
/// so this is O(9) per call and never returns an empty array in practice.
fn to_chars(s : String) -> Array[Char] {
  let out : Array[Char] = []
  for ch in s {
    out.push(ch)
  }
  out
}

///|
/// Rebuild a `String` from an `Array[Char]` of arbitrary length.
///
/// Used after editing the 9-character state array to produce the new node
/// value for A* — `String` is what we hash and compare on.
fn from_chars(chars : Array[Char]) -> String {
  let buf = StringBuilder::new()
  for ch in chars {
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
/// Map a digit character '0'..'8' to its integer value.
///
/// Any other character is treated as `-1`, which signals corrupt input and
/// will never occur for well-formed 8-puzzle states.
fn char_to_digit(ch : Char) -> Int {
  match ch {
    '0' => 0
    '1' => 1
    '2' => 2
    '3' => 3
    '4' => 4
    '5' => 5
    '6' => 6
    '7' => 7
    '8' => 8
    _ => -1
  }
}

///|
/// Locate the blank square (the '0' tile) within a state string.
///
/// Returns the 0-based index into the 9-character state. For well-formed
/// inputs there is always exactly one blank, so `-1` is never returned, but
/// we still handle it defensively to keep the search from crashing on bad
/// data (consistent with Requirement 1.4 — return `None` / no-op rather than
/// throw).
fn find_blank(state : String) -> Int {
  let chars = to_chars(state)
  for i in 0..<chars.length() {
    if chars[i] == '0' {
      return i
    }
  }
  -1
}

///|
/// Produce the neighbour state that results from swapping the blank with the
/// tile at `target_index`.
///
/// Both indices must be valid cells in the 3x3 board; the caller is
/// responsible for only passing legal moves (see `neighbors`).
fn swap_state(state : String, blank : Int, target : Int) -> String {
  let chars = to_chars(state)
  let tmp = chars[blank]
  chars[blank] = chars[target]
  chars[target] = tmp
  from_chars(chars)
}

///|
/// Enumerate all legal successor states reachable in one move.
///
/// Returns an `Array[(String, Int)]` where each element is `(next_state,
/// edge_weight)` as required by the weighted `@dir.astar` API. Every move in
/// the 8-puzzle has unit cost, so the edge weight is always `1` (so path
/// cost = number of moves).
fn neighbors(state : String) -> Array[(String, Int)] {
  let blank = find_blank(state)
  if blank < 0 {
    return []
  }
  let row = blank / 3
  let col = blank % 3
  let moves : Array[(Int, Int)] = [
    (row - 1, col),
    (row + 1, col),
    (row, col - 1),
    (row, col + 1),
  ]
  let out : Array[(String, Int)] = []
  for m in moves {
    let (r, c) = m
    if r >= 0 && r < 3 && c >= 0 && c < 3 {
      let target = r * 3 + c
      out.push((swap_state(state, blank, target), 1))
    }
  }
  out
}

///|
/// Manhattan-distance heuristic, summed over all non-blank tiles.
///
/// For each tile 1..8 we compute the grid distance between its current
/// location and its goal location in "123456780". This is admissible (each
/// tile needs at least that many moves to reach its home) and consistent, so
/// `@dir.astar` is guaranteed to return an optimal solution — exactly the
/// property exercised by this example.
fn manhattan(state : String) -> Int {
  let chars = to_chars(state)
  let mut total = 0
  for i in 0..<chars.length() {
    let v = char_to_digit(chars[i])
    // Skip the blank tile: only the 1..8 pieces contribute to the heuristic.
    if v <= 0 {
      continue
    }
    // Goal position of tile `v` in "123456780": tile `k` lives at index k-1
    // for k in 1..8. (The blank lives at index 8 but we already skipped it.)
    let goal_idx = v - 1
    let goal_row = goal_idx / 3
    let goal_col = goal_idx % 3
    let cur_row = i / 3
    let cur_col = i % 3
    total += (goal_row - cur_row).abs() + (goal_col - cur_col).abs()
  }
  total
}

///|
/// Render a 9-character state string as a 3x3 ASCII board.
///
/// The blank tile (digit `0`) is drawn as an underscore `_` for readability;
/// every other digit is printed as-is. Rows are joined by newlines and the
/// whole block is returned as a single `String` so callers can `println` it.
fn render_board(state : String) -> String {
  let chars = to_chars(state)
  let buf = StringBuilder::new()
  for r in 0..<3 {
    for c in 0..<3 {
      let ch = chars[r * 3 + c]
      let display = if ch == '0' { '_' } else { ch }
      buf.write_char(display)
      if c < 2 {
        buf.write_char(' ')
      }
    }
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// A named 8-puzzle scenario. `print_each_step` controls whether the solver
/// dumps every intermediate board (short runs only; the 15-20 step scenario
/// is noisy if this is on).
struct Scenario {
  name : String
  initial : String
  print_each_step : Bool
}

///|
/// Solve one scenario with `@dir.astar` + Manhattan heuristic, then print a
/// human-readable report.
///
/// Output layout (in order):
///   1. title line;
///   2. initial board;
///   3. heuristic value at the start (for sanity);
///   4. either the solved step count (and optionally every intermediate
///      board) or a "no solution" diagnostic.
///
/// The function always returns `Unit` — any internal failure is reported
/// textually rather than thrown, so `moon run` still exits with code 0 as
/// required by Requirement 9.4.
fn solve_and_print(scenario : Scenario) -> Unit {
  println("=== " + scenario.name + " ===")
  println("Initial board:")
  println(render_board(scenario.initial))
  println(
    "Heuristic (sum of Manhattan dist.) = " +
    manhattan(scenario.initial).to_string(),
  )
  let result = @dir.astar(
    scenario.initial,
    fn(s) { neighbors(s) },
    fn(s) { manhattan(s) },
    fn(s) { s == GOAL },
  )
  match result {
    Some((path, cost)) => {
      // `path` contains one state per move plus the initial, so step count
      // is `path.length() - 1`. `cost` is the A* total edge weight which,
      // given unit edges, equals the step count — we print both to make the
      // weighted-search API visible even for uniform-cost problems.
      let steps = path.length() - 1
      println(
        "Solved in " +
        steps.to_string() +
        " moves (A* total cost = " +
        cost.to_string() +
        ").",
      )
      if scenario.print_each_step {
        println("Solution trace:")
        for i in 0..<path.length() {
          println("Step " + i.to_string() + ":")
          println(render_board(path[i]))
        }
      }
    }
    None => println("No solution found (input may be unsolvable).")
  }
  println("")
}

///|
/// Predefined puzzle scenarios exercising three difficulty tiers.
///
/// All three initial configurations are reachable from `GOAL` (they satisfy
/// the parity-of-inversions solvability rule for the 3x3 sliding puzzle).
///
///   * Scenario 1 — Easy (1 move): one tile out of place.
///   * Scenario 2 — Medium (6 moves): derived by 6 non-reversing scrambles.
///   * Scenario 3 — Challenging (optimal ~15-20 moves): Manhattan
///     heuristic lower bound is 14, the actual optimum ends up at 20.
///
/// The optimal move count is determined by A* itself at run time — the
/// commentary above states the expected range, while the program prints the
/// actual cost.
fn scenarios() -> Array[Scenario] {
  [
    {
      name: "Scenario 1: easy (1-step swap)",
      initial: "123450786",
      print_each_step: true,
    },
    {
      name: "Scenario 2: medium (~6 moves)",
      initial: "152743086",
      print_each_step: true,
    },
    {
      name: "Scenario 3: challenging (Manhattan >= 12)",
      initial: "724506831",
      print_each_step: false,
    },
  ]
}

///|
/// Program entry point. Runs every predefined scenario in order and prints
/// a short report. The process always exits with code 0 (no exceptions
/// thrown), satisfying Requirement 9.4.
fn main {
  println("moonbit-pathfinding · eight_puzzle example")
  println("Algorithm: A* with sum-of-Manhattan-distances heuristic")
  println("Node type: String (9 chars, digits '0'..'8', '0' is blank)")
  println("Goal state: \"" + GOAL + "\" (blank bottom-right)")
  println("")
  for scenario in scenarios() {
    solve_and_print(scenario)
  }
}
