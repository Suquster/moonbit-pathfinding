// Core abstractions for moonbit-pathfinding.
//
// Defines the `Weight` trait (numeric abstraction for edge weights) and the
// `PathError` enum (shared error type for algorithms that can fail).

///|
/// The `Weight` trait abstracts edge-weight arithmetic for weighted graph
/// algorithms (Dijkstra, A*, Bellman-Ford, Floyd-Warshall, ALT, CH, ...).
///
/// A type implementing `Weight` must support:
/// - addition (associative, commutative)
/// - an identity `zero()` satisfying `x + zero() == x`
/// - an `infinity()` upper bound satisfying `infinity() > x` for all finite x
/// - total ordering (via the `Compare` superbound)
///
/// We intentionally do NOT require `Mul`, `Div`, or `Sub` because pathfinding
/// algorithms never need them; this keeps the trait implementable by exotic
/// weight types (e.g. tropical semirings, lexicographic tuples, ...).
pub(open) trait Weight: Compare + Eq {
  fn zero() -> Self
  fn infinity() -> Self
  fn add(Self, Self) -> Self

  /// Saturating subtraction: `sub(a, b)` returns `a - b` when `a >= b`,
  /// and `zero()` otherwise. The "saturating-at-zero" semantics are the
  /// correct choice for the **absolute-difference** use cases in the
  /// library (ALT heuristic, Bellman-Ford potential reweighing), where
  /// a negative result is never desired.
  fn sub(Self, Self) -> Self
}

///|
/// Additive identity for `Int` weights: returns `0`, the neutral element of
/// integer addition (`x + zero() == x`).
pub impl Weight for Int with fn zero() {
  0
}

///|
/// Upper bound for `Int` weights: returns `2^31 - 1` (`Int::max_value`).
/// Acts as "unreachable" sentinel in algorithms like Floyd-Warshall;
/// `add` is saturating so this value is absorbing.
pub impl Weight for Int with fn infinity() {
  // 2^31 - 1, far enough for practical graphs without overflowing on add.
  2147483647
}

///|
/// Saturating addition for `Int` weights. If either operand equals
/// `infinity()` (2^31 - 1), the result is also `infinity()`, preventing
/// wrap-around when relaxing edges adjacent to unreachable nodes.
pub impl Weight for Int with fn add(a, b) {
  // Saturating addition: if either operand is "infinity", stay at infinity.
  let inf : Int = 2147483647
  if a == inf || b == inf {
    inf
  } else {
    a + b
  }
}

///|
/// Additive identity for `Double` weights: returns `0.0`.
/// Satisfies `x + zero() == x` for every finite `Double`.
pub impl Weight for Double with fn zero() {
  0.0
}

///|
/// Upper bound for `Double` weights: returns IEEE-754 positive infinity
/// (`@double.infinity`). Propagates through addition by IEEE-754 rules,
/// so no explicit saturation branch is needed.
pub impl Weight for Double with fn infinity() {
  @double.infinity
}

///|
/// Addition for `Double` weights, delegating to IEEE-754 `+`.
/// Infinity absorption and NaN propagation follow IEEE-754 semantics.
pub impl Weight for Double with fn add(a, b) {
  a + b
}

///|
/// Saturating subtraction for `Int` weights.
/// Returns `a - b` when `a >= b`, otherwise `0`. Treats `infinity() - x`
/// as `infinity()` (absorbing), mirroring the add-side saturation.
pub impl Weight for Int with fn sub(a, b) {
  let inf : Int = 2147483647
  if a == inf {
    inf
  } else if a >= b {
    a - b
  } else {
    0
  }
}

///|
/// Saturating subtraction for `Double` weights.
/// Delegates to IEEE-754 `-`, then clamps any negative outcome to `0.0`
/// to preserve the "distance-like" non-negative invariant required by
/// ALT's triangle-inequality heuristic.
pub impl Weight for Double with fn sub(a, b) {
  let d = a - b
  if d < 0.0 {
    0.0
  } else {
    d
  }
}

///|
/// Canonical error type for pathfinding algorithms that can fail in
/// structured ways (as opposed to simply being unreachable, which uses
/// `Option` / `?`).
pub(all) enum PathError {
  /// Bellman-Ford detected a reachable negative cycle.
  NegativeCycle
  /// Topological sort detected a cycle in the alleged DAG.
  CycleDetected
  /// Algorithm-specific bad input (e.g. non-square cost matrix).
  InvalidInput(String)
  /// Yen's k-shortest was called with k <= 0.
  InvalidK(Int)
} derive(Debug, Eq)
