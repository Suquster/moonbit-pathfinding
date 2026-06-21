// Jump Point Search (JPS) — grid pathfinding that exploits symmetry.
//
// Reference: Harabor, D., & Grastien, A. (2011). "Online Graph Pruning for
// Pathfinding on Grid Maps." AAAI 2011.
//
// This implementation targets **uniform-cost grids** with 8-directional
// movement (the setting in which JPS is most impactful). For 4-directional
// movement, JPS's speedup vanishes (all successors become jump points) so
// callers should prefer plain A* on 4-neighbour grids.
//
// High-level structure:
//   * `JPSGrid` is the input: width × height plus a `blocked` flags array
//     (row-major).
//   * `jps(grid, start, goal)` runs A* with Octile heuristic, but uses
//     `identify_successors` + `jump` to collapse runs of "forced-move"
//     cells into a single heap push — turning O(grid area) into
//     O(number of obstacles + path length).
//
// Design note (per tasks.md 36.x + R18.1(b) / R18.2):
//   * The `jump` function walks the ray **iteratively** (no recursion on
//     the primary direction), and only recurses one level into the two
//     cardinal sub-directions when moving diagonally — those sub-jumps
//     are themselves iterative, so the total stack depth is O(1)
//     regardless of grid size.

///|
/// Uniform-cost grid of `width × height` cells with a blocking mask.
///
/// `blocked[r * width + c] == true` means the cell `(r, c)` is a wall.
/// All open cells carry unit move cost for cardinal steps; diagonal steps
/// have cost `sqrt(2)` (approximated as `1.4142135` in `Double`). A
/// diagonal move is only legal when **both** adjacent cardinal neighbours
/// are open — "no corner cutting", the standard grid rule.
pub struct JPSGrid {
  width : Int
  height : Int
  blocked : Array[Bool]
}

///|
/// Construct a `JPSGrid` from raw dimensions + blocking mask. Returns
/// `None` when the mask length does not match `width * height`, which is
/// the only way this constructor can fail.
pub fn JPSGrid::new(
  width : Int,
  height : Int,
  blocked : Array[Bool],
) -> JPSGrid? {
  if width <= 0 || height <= 0 {
    return None
  }
  if blocked.length() != width * height {
    return None
  }
  Some({ width, height, blocked })
}

///|
/// `true` iff `(r, c)` is inside the grid bounds.
fn JPSGrid::in_bounds(self : JPSGrid, r : Int, c : Int) -> Bool {
  r >= 0 && r < self.height && c >= 0 && c < self.width
}

///|
/// `true` iff `(r, c)` is in bounds and not a wall. Cells outside the grid
/// are treated as blocked, so out-of-bounds is a natural "dead end".
fn JPSGrid::walkable(self : JPSGrid, r : Int, c : Int) -> Bool {
  if !self.in_bounds(r, c) {
    return false
  }
  !self.blocked[r * self.width + c]
}

///|
/// Octile distance heuristic — the standard admissible estimate for
/// 8-directional grid A*. Equals `max(|dx|, |dy|) + (sqrt(2) - 1) * min(|dx|, |dy|)`.
fn octile(a : (Int, Int), b : (Int, Int)) -> Double {
  let (ar, ac) = a
  let (br, bc) = b
  let dx = (br - ar).abs().to_double()
  let dy = (bc - ac).abs().to_double()
  let big = if dx > dy { dx } else { dy }
  let small = if dx > dy { dy } else { dx }
  big + (1.4142135 - 1.0) * small
}

///|
/// Attempt to **jump** from `from` in direction `(dr, dc)`, iteratively
/// skipping cells that have no forced neighbours.
///
/// Returns `Some((r, c))` where `(r, c)` is the first jump-point reached
/// (either the goal, a cell with a forced neighbour, or an intermediate
/// point whose sub-direction jump succeeds). `None` means the ray either
/// exits the grid or runs into a wall without finding a jump-point.
fn JPSGrid::jump(
  self : JPSGrid,
  from_r : Int,
  from_c : Int,
  dr : Int,
  dc : Int,
  goal : (Int, Int),
) -> (Int, Int)? {
  let mut cr = from_r
  let mut cc = from_c
  while true {
    let nr = cr + dr
    let nc = cc + dc
    if !self.walkable(nr, nc) {
      return None
    }
    if (nr, nc) == goal {
      return Some((nr, nc))
    }
    // Forced-neighbour rule for cardinal moves:
    // A cardinal move (dr, dc) has a forced neighbour when one of the
    // perpendicular neighbours is blocked but the diagonal after it is open.
    if dr != 0 && dc == 0 {
      let forced_left = !self.walkable(nr, nc - 1) &&
        self.walkable(nr + dr, nc - 1)
      let forced_right = !self.walkable(nr, nc + 1) &&
        self.walkable(nr + dr, nc + 1)
      if forced_left || forced_right {
        return Some((nr, nc))
      }
    } else if dc != 0 && dr == 0 {
      let forced_up = !self.walkable(nr - 1, nc) &&
        self.walkable(nr - 1, nc + dc)
      let forced_down = !self.walkable(nr + 1, nc) &&
        self.walkable(nr + 1, nc + dc)
      if forced_up || forced_down {
        return Some((nr, nc))
      }
    } else {
      // Diagonal: forced-neighbour check plus cardinal sub-direction jumps.
      let diag_forced_a = !self.walkable(nr - dr, nc) &&
        self.walkable(nr - dr, nc + dc)
      let diag_forced_b = !self.walkable(nr, nc - dc) &&
        self.walkable(nr + dr, nc - dc)
      if diag_forced_a || diag_forced_b {
        return Some((nr, nc))
      }
      // Sub-direction jumps: either horizontal or vertical sub-jump found
      // ⇒ the current diagonal cell is itself a jump-point.
      if self.jump(nr, nc, dr, 0, goal) is Some(_) {
        return Some((nr, nc))
      }
      if self.jump(nr, nc, 0, dc, goal) is Some(_) {
        return Some((nr, nc))
      }
    }
    // Continue jumping in the same direction.
    cr = nr
    cc = nc
  }
  None
}

///|
/// The full 8-neighbour set for `(r, c)` as offsets.
fn neighbour_dirs() -> Array[(Int, Int)] {
  [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
}

///|
/// `identify_successors` — enumerate jump-points reachable from `node`.
///
/// For the first call (no parent) all 8 directions are tried. For
/// subsequent calls we prune directions using "natural / forced neighbour"
/// rules (see Harabor 2011 §4). Each surviving direction is `jump()`-ed
/// to yield at most one successor.
fn JPSGrid::identify_successors(
  self : JPSGrid,
  node : (Int, Int),
  parent : (Int, Int)?,
  goal : (Int, Int),
) -> Array[((Int, Int), Double)] {
  let (nr, nc) = node
  let dirs = match parent {
    None => neighbour_dirs() // root expansion — try every direction
    Some((pr, pc)) => {
      // Unit direction from parent to current node.
      let dr = sign(nr - pr)
      let dc = sign(nc - pc)
      let out : Array[(Int, Int)] = []
      if dr != 0 && dc != 0 {
        // Natural neighbours for diagonal: (dr, 0), (0, dc), (dr, dc).
        out.push((dr, 0))
        out.push((0, dc))
        out.push((dr, dc))
      } else if dr != 0 {
        out.push((dr, 0))
        // Forced neighbours: blocked perpendicular opens a diagonal.
        if !self.walkable(nr, nc - 1) {
          out.push((dr, -1))
        }
        if !self.walkable(nr, nc + 1) {
          out.push((dr, 1))
        }
      } else {
        out.push((0, dc))
        if !self.walkable(nr - 1, nc) {
          out.push((-1, dc))
        }
        if !self.walkable(nr + 1, nc) {
          out.push((1, dc))
        }
      }
      out
    }
  }
  let succ : Array[((Int, Int), Double)] = []
  for d in dirs {
    let (dr, dc) = d
    match self.jump(nr, nc, dr, dc, goal) {
      Some(jp) => {
        let (jr, jc) = jp
        // Cost along the jump-ray = Chebyshev distance scaled by step cost.
        let steps_r = (jr - nr).abs()
        let steps_c = (jc - nc).abs()
        let diag_steps = if steps_r < steps_c { steps_r } else { steps_c }
        let straight_steps = if steps_r > steps_c {
          steps_r - steps_c
        } else {
          steps_c - steps_r
        }
        let cost = diag_steps.to_double() * 1.4142135 +
          straight_steps.to_double()
        succ.push((jp, cost))
      }
      None => ()
    }
  }
  succ
}

///|
/// Signum function on integers (-1, 0, or 1). Used to extract move
/// direction from (current − parent) deltas.
fn sign(x : Int) -> Int {
  if x > 0 {
    1
  } else if x < 0 {
    -1
  } else {
    0
  }
}

///|
/// JPS shortest path from `start` to `goal` on a uniform-cost grid.
///
/// Returns `Some((path, cost))` where `path` contains all jump-points
/// (including `start` and `goal`; intermediate "regular" cells are omitted
/// because JPS treats them as equivalent to the jump points). `cost` is
/// the total Octile distance of the route.
///
/// Complexity: O(N log N) where N is the number of jump-points, which is
/// typically O(√area) on uniform grids — much less than the full A*
/// O(area).
pub fn jps(
  grid : JPSGrid,
  start : (Int, Int),
  goal : (Int, Int),
) -> (Array[(Int, Int)], Double)? {
  let (sr, sc) = start
  let (gr, gc) = goal
  if !grid.walkable(sr, sc) || !grid.walkable(gr, gc) {
    return None
  }
  if start == goal {
    return Some(([start], 0.0))
  }
  let g_cost : Map[(Int, Int), Double] = Map([])
  let parents : Map[(Int, Int), (Int, Int)] = Map([])
  // Payload carries the `g` recorded at push time so stale (superseded)
  // entries can be skipped on pop, avoiding redundant jump-point expansions.
  let pq : @core.PQueue[((Int, Int), Double), Double] = @core.PQueue::new()
  g_cost[start] = 0.0
  pq.push(octile(start, goal), (start, 0.0))
  while !pq.is_empty() {
    let (_, (u, gu_entry)) = pq.pop().unwrap()
    match g_cost.get(u) {
      Some(best) => if gu_entry > best { continue }
      None => continue
    }
    if u == goal {
      // Reconstruct path by walking parents back to start.
      let path = [u]
      let mut node = u
      while node != start {
        match parents.get(node) {
          Some(p) => {
            node = p
            path.push(node)
          }
          None => break
        }
      }
      path.rev_in_place()
      let total = g_cost.get(u).unwrap()
      return Some((path, total))
    }
    let parent_of_u = parents.get(u)
    let successors = grid.identify_successors(u, parent_of_u, goal)
    let gu = gu_entry
    for pair in successors {
      let (v, w) = pair
      let tentative = gu + w
      let improve = match g_cost.get(v) {
        Some(existing) => tentative < existing
        None => true
      }
      if improve {
        g_cost[v] = tentative
        parents[v] = u
        let f = tentative + octile(v, goal)
        pq.push(f, (v, tentative))
      }
    }
  }
  None
}
