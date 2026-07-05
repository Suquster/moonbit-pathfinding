// hamt.mbt —— E1 核心数据结构：持久化（不可变）HashMap（HAMT）。
//
// paper-to-code：Bagwell. *Ideal Hash Trees.* 2001（Clojure/Scala 持久化
// 集合的底层结构）。32 叉字典树按 32 位哈希每 5 位分片下降，节点用
// **bitmap + 紧凑子数组**存储：popcount(bitmap & (bit-1)) 给出子节点在数组
// 中的物理下标——空槽零占用，故稀疏节点省内存、稠密节点仍 O(1) 定位。
//
// 不可变：insert/remove 走**路径复制**（path copying），只重建根到目标的
// O(log32 n) 条节点，其余子树与旧版本结构共享——旧引用永远有效，天然支持
// 多版本/持久化快照。
//
// 冲突（32 位哈希相等）落 Collision 节点线性存储。
//
// 对外 API：new / size / get / contains / insert / remove / to_array。

///|
enum HNode[K, V] {
  /// bitmap 指示 32 槽中哪些非空；children 紧凑存储（popcount 定位）。
  Branch(UInt, Array[HNode[K, V]])
  /// 叶：单键值对（存哈希以便下降比较）。
  Leaf(UInt, K, V)
  /// 哈希冲突桶：同 32 位哈希的多条目。
  Collision(UInt, Array[(K, V)])
}

///|
/// 持久化 HashMap：键需 Eq + Hash。根可空（空表 root=None）。
pub struct HamtMap[K, V] {
  root : HNode[K, V]?
  size : Int
}

///|
/// 每层分片位数（32/5 ≈ 7 层覆盖 32 位哈希）。
const HAMT_BITS : Int = 5

///|
const HAMT_MASK : UInt = 31

///|
/// 空表。
pub fn[K, V] HamtMap::new() -> HamtMap[K, V] {
  { root: None, size: 0 }
}

///|
/// 元素个数。
pub fn[K, V] HamtMap::length(self : HamtMap[K, V]) -> Int {
  self.size
}

///|
/// 取 hash 在 shift 处的 5 位分片。
fn shard(hash : UInt, shift : Int) -> Int {
  ((hash >> shift) & HAMT_MASK).reinterpret_as_int()
}

///|
/// bitmap 中 idx 位之前的置位数 = 子数组物理下标。
fn sparse_index(bitmap : UInt, idx : Int) -> Int {
  popcount_u(bitmap & ((1U << idx) - 1))
}

///|
fn popcount_u(x : UInt) -> Int {
  let mut v = x
  v = v - ((v >> 1) & 0x55555555U)
  v = (v & 0x33333333U) + ((v >> 2) & 0x33333333U)
  v = (v + (v >> 4)) & 0x0F0F0F0FU
  ((v * 0x01010101U) >> 24).reinterpret_as_int()
}

///|
/// 查找。
pub fn[K : Eq + Hash, V] HamtMap::get(self : HamtMap[K, V], key : K) -> V? {
  match self.root {
    None => None
    Some(node) => node_get(node, key, key.hash().reinterpret_as_uint(), 0)
  }
}

///|
fn[K : Eq, V] node_get(
  node : HNode[K, V],
  key : K,
  hash : UInt,
  shift : Int,
) -> V? {
  match node {
    Leaf(_, k, v) => if k == key { Some(v) } else { None }
    Collision(_, entries) => {
      for e in entries {
        if e.0 == key {
          return Some(e.1)
        }
      }
      None
    }
    Branch(bitmap, children) => {
      let idx = shard(hash, shift)
      let bit = 1U << idx
      if (bitmap & bit) == 0 {
        None
      } else {
        node_get(
          children[sparse_index(bitmap, idx)],
          key,
          hash,
          shift + HAMT_BITS,
        )
      }
    }
  }
}

///|
/// 是否含键。
pub fn[K : Eq + Hash, V] HamtMap::contains(
  self : HamtMap[K, V],
  key : K,
) -> Bool {
  self.get(key) is Some(_)
}

///|
/// 在紧凑子数组 idx 处插入新元素（返回新数组，不改旧数组——路径复制）。
fn[T] arr_inserted(a : Array[T], idx : Int, x : T) -> Array[T] {
  let out : Array[T] = []
  for i in 0..<idx {
    out.push(a[i])
  }
  out.push(x)
  for i in idx..<a.length() {
    out.push(a[i])
  }
  out
}

///|
/// 替换紧凑子数组 idx 处元素（返回新数组）。
fn[T] arr_replaced(a : Array[T], idx : Int, x : T) -> Array[T] {
  let out = a.copy()
  out[idx] = x
  out
}

///|
/// 删除紧凑子数组 idx 处元素（返回新数组）。
fn[T] arr_removed(a : Array[T], idx : Int) -> Array[T] {
  let out : Array[T] = []
  for i in 0..<a.length() {
    if i != idx {
      out.push(a[i])
    }
  }
  out
}

///|
/// 插入/更新，返回**新表**（旧表不变）。
pub fn[K : Eq + Hash, V] HamtMap::insert(
  self : HamtMap[K, V],
  key : K,
  value : V,
) -> HamtMap[K, V] {
  let hash = key.hash().reinterpret_as_uint()
  match self.root {
    None => { root: Some(Leaf(hash, key, value)), size: 1 }
    Some(node) => {
      let added : Array[Bool] = [false]
      let new_root = node_insert(node, key, value, hash, 0, added)
      { root: Some(new_root), size: self.size + (if added[0] { 1 } else { 0 }) }
    }
  }
}

///|
/// 把两条不同哈希的叶合并成子树（从 shift 层继续分叉）。
fn[K, V] merge_leaves(
  h1 : UInt,
  k1 : K,
  v1 : V,
  n2 : HNode[K, V],
  h2 : UInt,
  shift : Int,
) -> HNode[K, V] {
  let i1 = shard(h1, shift)
  let i2 = shard(h2, shift)
  if i1 == i2 {
    // 同槽继续深分。
    let child = merge_leaves(h1, k1, v1, n2, h2, shift + HAMT_BITS)
    Branch(1U << i1, [child])
  } else {
    let b1 = 1U << i1
    let b2 = 1U << i2
    let leaf1 = Leaf(h1, k1, v1)
    if i1 < i2 {
      Branch(b1 | b2, [leaf1, n2])
    } else {
      Branch(b1 | b2, [n2, leaf1])
    }
  }
}

///|
fn[K : Eq, V] node_insert(
  node : HNode[K, V],
  key : K,
  value : V,
  hash : UInt,
  shift : Int,
  added : Array[Bool],
) -> HNode[K, V] {
  match node {
    Leaf(lh, lk, lv) =>
      if lk == key {
        Leaf(lh, key, value)
      } else if lh == hash {
        added[0] = true
        Collision(hash, [(lk, lv), (key, value)])
      } else {
        added[0] = true
        merge_leaves(hash, key, value, Leaf(lh, lk, lv), lh, shift)
      }
    Collision(ch, entries) =>
      if ch == hash {
        for i in 0..<entries.length() {
          if entries[i].0 == key {
            return Collision(ch, arr_replaced(entries, i, (key, value)))
          }
        }
        added[0] = true
        Collision(ch, arr_inserted(entries, entries.length(), (key, value)))
      } else {
        // 冲突桶与新键哈希不同：升一层 Branch 再插。
        added[0] = true
        let bidx = shard(ch, shift)
        let branch : HNode[K, V] = Branch(1U << bidx, [node])
        node_insert(branch, key, value, hash, shift, added)
      }
    Branch(bitmap, children) => {
      let idx = shard(hash, shift)
      let bit = 1U << idx
      let pos = sparse_index(bitmap, idx)
      if (bitmap & bit) == 0 {
        added[0] = true
        Branch(
          bitmap | bit,
          arr_inserted(children, pos, Leaf(hash, key, value)),
        )
      } else {
        let child = node_insert(
          children[pos],
          key,
          value,
          hash,
          shift + HAMT_BITS,
          added,
        )
        Branch(bitmap, arr_replaced(children, pos, child))
      }
    }
  }
}

///|
/// 删除，返回**新表**（旧表不变）。
pub fn[K : Eq + Hash, V] HamtMap::remove(
  self : HamtMap[K, V],
  key : K,
) -> HamtMap[K, V] {
  match self.root {
    None => self
    Some(node) => {
      let removed : Array[Bool] = [false]
      let new_root = node_remove(
        node,
        key,
        key.hash().reinterpret_as_uint(),
        0,
        removed,
      )
      if removed[0] {
        { root: new_root, size: self.size - 1 }
      } else {
        self
      }
    }
  }
}

///|
fn[K : Eq, V] node_remove(
  node : HNode[K, V],
  key : K,
  hash : UInt,
  shift : Int,
  removed : Array[Bool],
) -> HNode[K, V]? {
  match node {
    Leaf(_, lk, _) =>
      if lk == key {
        removed[0] = true
        None
      } else {
        Some(node)
      }
    Collision(ch, entries) => {
      for i in 0..<entries.length() {
        if entries[i].0 == key {
          removed[0] = true
          let rest = arr_removed(entries, i)
          if rest.length() == 1 {
            return Some(Leaf(ch, rest[0].0, rest[0].1))
          }
          return Some(Collision(ch, rest))
        }
      }
      Some(node)
    }
    Branch(bitmap, children) => {
      let idx = shard(hash, shift)
      let bit = 1U << idx
      if (bitmap & bit) == 0 {
        return Some(node)
      }
      let pos = sparse_index(bitmap, idx)
      let child_res = node_remove(
        children[pos],
        key,
        hash,
        shift + HAMT_BITS,
        removed,
      )
      match child_res {
        Some(c) => Some(Branch(bitmap, arr_replaced(children, pos, c)))
        None => {
          let new_children = arr_removed(children, pos)
          let new_bitmap = bitmap ^ bit
          if new_children.length() == 0 {
            None
          } else if new_children.length() == 1 && is_terminal(new_children[0]) {
            // 塌缩：单个终端子节点上提，保持结构最小。
            Some(new_children[0])
          } else {
            Some(Branch(new_bitmap, new_children))
          }
        }
      }
    }
  }
}

///|
/// 终端节点（叶或冲突桶）可在删除后上提塌缩。
fn[K, V] is_terminal(node : HNode[K, V]) -> Bool {
  match node {
    Branch(_, _) => false
    _ => true
  }
}

///|
/// 全量导出（顺序由 trie 结构决定，稳定但非键序）。
pub fn[K, V] HamtMap::to_array(self : HamtMap[K, V]) -> Array[(K, V)] {
  let out : Array[(K, V)] = []
  match self.root {
    None => ()
    Some(node) => collect(node, out)
  }
  out
}

///|
fn[K, V] collect(node : HNode[K, V], out : Array[(K, V)]) -> Unit {
  match node {
    Leaf(_, k, v) => out.push((k, v))
    Collision(_, entries) =>
      for e in entries {
        out.push(e)
      }
    Branch(_, children) =>
      for c in children {
        collect(c, out)
      }
  }
}
