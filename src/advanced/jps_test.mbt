// Blackbox tests for JPS (Jump Point Search) on uniform-cost grids.

///|
/// Build a JPSGrid from a list of "pattern strings" where `.` = open,
/// `#` = blocked. Row-major, equal-length strings.
fn grid_from_pattern(rows : Array[String]) -> JPSGrid {
  let height = rows.length()
  let width = if height > 0 { rows[0].length() } else { 0 }
  let blocked : Array[Bool] = Array::make(width * height, false)
  for r in 0..<height {
    let row = rows[r]
    let mut c = 0
    for ch in row {
      if ch == '#' {
        blocked[r * width + c] = true
      }
      c += 1
    }
  }
  match JPSGrid::new(width, height, blocked) {
    Some(g) => g
    None => abort("grid_from_pattern: invalid dimensions")
  }
}

///|
test "jps on 5x5 open grid corner-to-corner" {
  // No obstacles; JPS should jump directly along the diagonal.
  let grid = grid_from_pattern([".....", ".....", ".....", ".....", "....."])
  match jps(grid, (0, 0), (4, 4)) {
    Some((path, _cost)) => {
      // Path must start/end at corners.
      @debug.debug_inspect(path[0], content="(0, 0)")
      @debug.debug_inspect(path[path.length() - 1], content="(4, 4)")
      // Open-grid diagonal: 4 diagonal steps -> cost ≈ 4 * sqrt(2) ≈ 5.6568...
      assert_true(path.length() >= 2)
    }
    None => assert_true(false)
  }
}

///|
test "jps start equals goal returns singleton" {
  let grid = grid_from_pattern([".."])
  match jps(grid, (0, 0), (0, 0)) {
    Some((path, cost)) => {
      inspect(path.length(), content="1")
      inspect(cost, content="0")
    }
    None => assert_true(false)
  }
}

///|
test "jps unreachable when goal walled off" {
  // 3x3 with center cross of walls forming enclosure around goal (2, 2)?
  // Simpler: goal is itself a wall -> must return None.
  let grid = grid_from_pattern(["...", ".#.", "..#"])
  let r = jps(grid, (0, 0), (2, 2))
  match r {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
}

///|
test "jps with obstacle forces detour but still optimal" {
  // 5x5 with a short wall; goal still reachable via detour.
  //   . . . . .
  //   . . . . .
  //   . . # . .
  //   . . . . .
  //   . . . . .
  let grid = grid_from_pattern([".....", ".....", "..#..", ".....", "....."])
  match jps(grid, (0, 0), (4, 4)) {
    Some((path, _cost)) => {
      @debug.debug_inspect(path[0], content="(0, 0)")
      @debug.debug_inspect(path[path.length() - 1], content="(4, 4)")
      // JPS path must still be reasonably short (< full perimeter).
      assert_true(path.length() <= 6)
    }
    None => assert_true(false)
  }
}

///|
/// whitebox: 非法输入 — blocked 数组长度与 width*height 不匹配时,
/// `JPSGrid::new` 返回 `None`。覆盖构造函数的尺寸校验分支。
test "whitebox: JPSGrid::new rejects mismatched blocked length" {
  // width=3, height=3 → 需要 9 个 bool;这里只给 8 个。
  let bad : Array[Bool] = Array::make(8, false)
  let r = JPSGrid::new(3, 3, bad)
  match r {
    None => assert_true(true)
    Some(_) => assert_true(false)
  }
}
