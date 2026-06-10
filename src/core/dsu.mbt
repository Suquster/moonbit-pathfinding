// Disjoint Set Union (Union-Find) with path compression and union by rank.
//
// Used by Kruskal's MST, and useful anywhere equivalence-class tracking is
// needed during a graph traversal.

///|
/// Disjoint Set Union over nodes of type `N : Eq + Hash`.
///
/// Supports `find` (with path compression) and `union` (by rank) both in
/// amortized near-constant time (O(α(n)) where α is the inverse Ackermann).
pub struct DSU[N] {
  priv parent : Map[N, N]
  priv rank : Map[N, Int]
}

///|
/// Create an empty DSU.
pub fn[N] DSU::new() -> DSU[N] {
  { parent: Map::new(), rank: Map::new() }
}

///|
/// Ensure `x` is present in the DSU (as its own singleton component).
pub fn[N : Eq + Hash] DSU::make_set(self : DSU[N], x : N) -> Unit {
  if !self.parent.contains(x) {
    self.parent[x] = x
    self.rank[x] = 0
  }
}

///|
/// Find the representative of `x`'s component, applying path compression.
pub fn[N : Eq + Hash] DSU::find(self : DSU[N], x : N) -> N {
  self.make_set(x)
  let p = self.parent.get(x).unwrap()
  if p == x {
    return x
  }
  let root = self.find(p)
  self.parent[x] = root
  root
}

///|
/// Merge the components containing `x` and `y`, returning `true` if they
/// were previously disjoint (i.e. a real merge occurred), `false` otherwise.
pub fn[N : Eq + Hash] DSU::union(self : DSU[N], x : N, y : N) -> Bool {
  let rx = self.find(x)
  let ry = self.find(y)
  if rx == ry {
    return false
  }
  let rank_x = self.rank.get(rx).unwrap()
  let rank_y = self.rank.get(ry).unwrap()
  if rank_x < rank_y {
    self.parent[rx] = ry
  } else if rank_x > rank_y {
    self.parent[ry] = rx
  } else {
    self.parent[ry] = rx
    self.rank[rx] = rank_x + 1
  }
  true
}

///|
/// Whether `x` and `y` are currently in the same component.
pub fn[N : Eq + Hash] DSU::same(self : DSU[N], x : N, y : N) -> Bool {
  self.find(x) == self.find(y)
}
