// btree.mbt —— E1 核心数据结构：B-tree 有序映射（BTreeMap）。
//
// paper-to-code：CLRS §18（B-Trees）。最小度数 t = 8：每个非根节点
// keys ∈ [t-1, 2t-1]（即 7..15），分支因子至多 2t=16——节点内键连续存储、
// 二分查找，兼顾缓存友好与树高 O(log_t n)。
//
// 单趟下降（single-pass）不回溯：
//   * 插入：下降途中遇满节点先分裂（CLRS 18.2 preemptive split）；
//   * 删除：下降途中保证子节点 keys ≥ t（CLRS 18.3 case 3a 借位 / 3b 合并），
//     内部命中用前驱替换后继续在子树删除（case 2）。
//
// 对外 API：new / size / get / contains / insert / remove / range / to_array。

///|
/// B-tree 节点：`kids` 为空即叶子；不变量 `kids.length() == keys.length()+1`
/// （内部节点）。
struct BNode[K, V] {
  keys : Array[K]
  vals : Array[V]
  kids : Array[BNode[K, V]]
}

///|
/// 最小度数 t（CLRS）：非根节点 keys ∈ [t-1, 2t-1]。
const BTREE_T : Int = 8

///|
fn[K, V] bnode_new() -> BNode[K, V] {
  { keys: [], vals: [], kids: [] }
}

///|
/// 有序映射：键类型需全序（Compare）。字段私有，仅经方法访问。
pub struct BTreeMap[K, V] {
  mut root : BNode[K, V]
  mut count : Int
}

///|
/// 空映射。
pub fn[K, V] BTreeMap::new() -> BTreeMap[K, V] {
  { root: bnode_new(), count: 0 }
}

///|
/// 键值对个数。
pub fn[K, V] BTreeMap::size(self : BTreeMap[K, V]) -> Int {
  self.count
}

///|
/// 节点内下界二分：返回首个 `keys[i] >= key` 的 i（不存在则 keys.length()）。
fn[K : Compare, V] lower_bound(node : BNode[K, V], key : K) -> Int {
  let mut lo = 0
  let mut hi = node.keys.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if node.keys[mid].compare(key) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// 查找。
pub fn[K : Compare, V] BTreeMap::get(self : BTreeMap[K, V], key : K) -> V? {
  let mut node = self.root
  while true {
    let i = lower_bound(node, key)
    if i < node.keys.length() && node.keys[i].compare(key) == 0 {
      return Some(node.vals[i])
    }
    if node.kids.length() == 0 {
      return None
    }
    node = node.kids[i]
  }
  None
}

///|
/// 是否含键。
pub fn[K : Compare, V] BTreeMap::contains(
  self : BTreeMap[K, V],
  key : K,
) -> Bool {
  self.get(key) is Some(_)
}

///|
/// 在数组 idx 处插入（手写移位，摊还 O(节点宽)）。
fn[T] arr_insert(a : Array[T], idx : Int, x : T) -> Unit {
  a.push(x)
  let mut i = a.length() - 1
  while i > idx {
    a[i] = a[i - 1]
    i = i - 1
  }
  a[idx] = x
}

///|
/// 移除并返回数组 idx 处元素。
fn[T] arr_remove(a : Array[T], idx : Int) -> T {
  let x = a[idx]
  let mut i = idx
  while i < a.length() - 1 {
    a[i] = a[i + 1]
    i = i + 1
  }
  let _ = a.pop()
  x
}

///|
/// 分裂满子节点 `parent.kids[i]`（keys 数 == 2t-1）：中位键上提到 parent，
/// 右半成为新兄弟（CLRS B-TREE-SPLIT-CHILD）。
fn[K, V] split_child(parent : BNode[K, V], i : Int) -> Unit {
  let child = parent.kids[i]
  let right : BNode[K, V] = bnode_new()
  let mid = BTREE_T - 1
  // 右半键值（mid+1 .. 2t-2）。
  for j in (mid + 1)..<child.keys.length() {
    right.keys.push(child.keys[j])
    right.vals.push(child.vals[j])
  }
  if child.kids.length() > 0 {
    for j in BTREE_T..<child.kids.length() {
      right.kids.push(child.kids[j])
    }
    child.kids.truncate(BTREE_T)
  }
  let up_k = child.keys[mid]
  let up_v = child.vals[mid]
  child.keys.truncate(mid)
  child.vals.truncate(mid)
  arr_insert(parent.keys, i, up_k)
  arr_insert(parent.vals, i, up_v)
  arr_insert(parent.kids, i + 1, right)
}

///|
/// 插入/更新；返回旧值（若键已存在）。
pub fn[K : Compare, V] BTreeMap::insert(
  self : BTreeMap[K, V],
  key : K,
  value : V,
) -> V? {
  // 根满则先升高一层再下降（保证下降路径永不满）。
  if self.root.keys.length() == 2 * BTREE_T - 1 {
    let new_root : BNode[K, V] = bnode_new()
    new_root.kids.push(self.root)
    split_child(new_root, 0)
    self.root = new_root
  }
  let mut node = self.root
  while true {
    let mut i = lower_bound(node, key)
    if i < node.keys.length() && node.keys[i].compare(key) == 0 {
      let old = node.vals[i]
      node.vals[i] = value
      return Some(old)
    }
    if node.kids.length() == 0 {
      arr_insert(node.keys, i, key)
      arr_insert(node.vals, i, value)
      self.count = self.count + 1
      return None
    }
    if node.kids[i].keys.length() == 2 * BTREE_T - 1 {
      split_child(node, i)
      let c = node.keys[i].compare(key)
      if c == 0 {
        let old = node.vals[i]
        node.vals[i] = value
        return Some(old)
      }
      if c < 0 {
        i = i + 1
      }
    }
    node = node.kids[i]
  }
  None
}

///|
/// 合并 `parent.kids[i]`、分隔键与 `parent.kids[i+1]`（两子均为 t-1 键时，
/// CLRS case 3b）。
fn[K, V] merge_children(parent : BNode[K, V], i : Int) -> Unit {
  let left = parent.kids[i]
  let right = parent.kids[i + 1]
  left.keys.push(arr_remove(parent.keys, i))
  left.vals.push(arr_remove(parent.vals, i))
  for j in 0..<right.keys.length() {
    left.keys.push(right.keys[j])
    left.vals.push(right.vals[j])
  }
  for j in 0..<right.kids.length() {
    left.kids.push(right.kids[j])
  }
  let _ = arr_remove(parent.kids, i + 1)
}

///|
/// 保证 `node.kids[i]` 至少 t 个键（下降前置，CLRS case 3a 借位 / 3b 合并）。
/// 返回（可能因合并而改变的）应继续下降的孩子下标。
fn[K, V] ensure_child(node : BNode[K, V], i : Int) -> Int {
  if node.kids[i].keys.length() >= BTREE_T {
    return i
  }
  // 左兄弟借位。
  if i > 0 && node.kids[i - 1].keys.length() >= BTREE_T {
    let child = node.kids[i]
    let left = node.kids[i - 1]
    arr_insert(child.keys, 0, node.keys[i - 1])
    arr_insert(child.vals, 0, node.vals[i - 1])
    node.keys[i - 1] = left.keys[left.keys.length() - 1]
    node.vals[i - 1] = left.vals[left.vals.length() - 1]
    let _ = left.keys.pop()
    let _ = left.vals.pop()
    if left.kids.length() > 0 {
      arr_insert(child.kids, 0, left.kids[left.kids.length() - 1])
      let _ = left.kids.pop()
    }
    return i
  }
  // 右兄弟借位。
  if i < node.kids.length() - 1 && node.kids[i + 1].keys.length() >= BTREE_T {
    let child = node.kids[i]
    let right = node.kids[i + 1]
    child.keys.push(node.keys[i])
    child.vals.push(node.vals[i])
    node.keys[i] = arr_remove(right.keys, 0)
    node.vals[i] = arr_remove(right.vals, 0)
    if right.kids.length() > 0 {
      child.kids.push(arr_remove(right.kids, 0))
    }
    return i
  }
  // 与相邻兄弟合并。
  if i > 0 {
    merge_children(node, i - 1)
    i - 1
  } else {
    merge_children(node, i)
    i
  }
}

///|
/// 删除；返回被删值（键不存在则 None）。
pub fn[K : Compare, V] BTreeMap::remove(self : BTreeMap[K, V], key : K) -> V? {
  let removed = remove_from(self.root, key)
  // 根缩层：内部根空键时其唯一孩子成为新根。
  if self.root.keys.length() == 0 && self.root.kids.length() > 0 {
    self.root = self.root.kids[0]
  }
  if removed is Some(_) {
    self.count = self.count - 1
  }
  removed
}

///|
/// 在保证 `node` 键数 ≥ t（或为根）的前提下递归删除。
fn[K : Compare, V] remove_from(node : BNode[K, V], key : K) -> V? {
  let i = lower_bound(node, key)
  let hit = i < node.keys.length() && node.keys[i].compare(key) == 0
  if node.kids.length() == 0 {
    // 叶：直接删（case 1）。
    if hit {
      let _ = arr_remove(node.keys, i)
      return Some(arr_remove(node.vals, i))
    }
    return None
  }
  if hit {
    // 内部命中（case 2）：左子够厚 → 前驱上提；右子够厚 → 后继上提；
    // 否则合并两子后在合并子树中删。
    let old = node.vals[i]
    if node.kids[i].keys.length() >= BTREE_T {
      let (pk, pv) = max_entry(node.kids[i])
      node.keys[i] = pk
      node.vals[i] = pv
      let _ = remove_from(node.kids[i], pk)
      return Some(old)
    } else if node.kids[i + 1].keys.length() >= BTREE_T {
      let (sk, sv) = min_entry(node.kids[i + 1])
      node.keys[i] = sk
      node.vals[i] = sv
      let _ = remove_from(node.kids[i + 1], sk)
      return Some(old)
    } else {
      merge_children(node, i)
      return remove_from(node.kids[i], key)
    }
  }
  let j = ensure_child(node, i)
  remove_from(node.kids[j], key)
}

///|
/// 子树最大条目（前驱）。
fn[K, V] max_entry(node : BNode[K, V]) -> (K, V) {
  let mut n = node
  while n.kids.length() > 0 {
    n = n.kids[n.kids.length() - 1]
  }
  (n.keys[n.keys.length() - 1], n.vals[n.vals.length() - 1])
}

///|
/// 子树最小条目（后继）。
fn[K, V] min_entry(node : BNode[K, V]) -> (K, V) {
  let mut n = node
  while n.kids.length() > 0 {
    n = n.kids[0]
  }
  (n.keys[0], n.vals[0])
}

///|
/// 半开区间 `[lo, hi)` 范围扫描：升序收集键值对，复杂度 O(log n + 命中数)。
pub fn[K : Compare, V] BTreeMap::range(
  self : BTreeMap[K, V],
  lo : K,
  hi : K,
) -> Array[(K, V)] {
  let out : Array[(K, V)] = []
  range_collect(self.root, lo, hi, out)
  out
}

///|
fn[K : Compare, V] range_collect(
  node : BNode[K, V],
  lo : K,
  hi : K,
  out : Array[(K, V)],
) -> Unit {
  let start = lower_bound(node, lo)
  let mut i = start
  while true {
    if node.kids.length() > 0 && i < node.kids.length() {
      // 子树可能含区间元素才下钻（左界剪枝由 lower_bound 提供，右界在此判断）。
      if i == start || node.keys[i - 1].compare(hi) < 0 {
        range_collect(node.kids[i], lo, hi, out)
      }
    }
    if i >= node.keys.length() {
      break
    }
    if node.keys[i].compare(hi) >= 0 {
      break
    }
    if node.keys[i].compare(lo) >= 0 {
      out.push((node.keys[i], node.vals[i]))
    }
    i = i + 1
  }
}

///|
/// 全量升序导出。
pub fn[K, V] BTreeMap::to_array(self : BTreeMap[K, V]) -> Array[(K, V)] {
  let out : Array[(K, V)] = []
  inorder(self.root, out)
  out
}

///|
fn[K, V] inorder(node : BNode[K, V], out : Array[(K, V)]) -> Unit {
  let n = node.keys.length()
  for i in 0..<n {
    if node.kids.length() > 0 {
      inorder(node.kids[i], out)
    }
    out.push((node.keys[i], node.vals[i]))
  }
  if node.kids.length() > 0 {
    inorder(node.kids[n], out)
  }
}
