// skiplist.mbt —— E1 核心数据结构：确定性跳表（SkipList）有序映射。
//
// paper-to-code：Pugh. *Skip Lists: A Probabilistic Alternative to Balanced
// Trees.* CACM 1990。多层有序链表，每个节点以概率 p=1/2 晋升到上一层，
// 查找/插入/删除自顶向下逐层前进，期望 O(log n)。
//
// **确定性**：层高由跳表自持的 xorshift64 随机源（构造种子固定）决定——同种子、
// 同操作序列产生完全一致的结构与结果，满足 DST/PBT 可复现前提（不依赖系统熵）。
//
// 对外 API：new / with_seed / size / get / contains / insert / remove /
// range / to_array。

///|
const SKIP_MAXLEVEL : Int = 24

///|
struct SkipNode[K, V] {
  key : K
  mut value : V
  /// forward[i] 为第 i 层的后继（None 表示该层到尾）。
  forward : Array[SkipNode[K, V]?]
}

///|
/// 有序映射：键需全序（Compare）。
pub struct SkipList[K, V] {
  /// 哨兵头节点（不存键值，forward 指向各层首个真实节点）。
  mut head : SkipNode[K, V]?
  mut level : Int
  mut count : Int
  mut rng : UInt64
}

///|
/// 以固定默认种子构造（确定性）。
pub fn[K, V] SkipList::new() -> SkipList[K, V] {
  SkipList::with_seed(0x9E3779B97F4A7C15UL)
}

///|
/// 以指定种子构造（确定性层高，便于复现）。
pub fn[K, V] SkipList::with_seed(seed : UInt64) -> SkipList[K, V] {
  let s = if seed == 0 { 0x9E3779B97F4A7C15UL } else { seed }
  { head: None, level: 0, count: 0, rng: s }
}

///|
/// 元素个数。
pub fn[K, V] SkipList::size(self : SkipList[K, V]) -> Int {
  self.count
}

///|
/// 推进随机源（xorshift64）。
fn[K, V] SkipList::next_rng(self : SkipList[K, V]) -> UInt64 {
  let mut x = self.rng
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  self.rng = x
  x
}

///|
/// 随机层高：几何分布 p=1/2，上限 SKIP_MAXLEVEL。
fn[K, V] SkipList::random_level(self : SkipList[K, V]) -> Int {
  let mut lvl = 1
  while (self.next_rng() & 1UL) == 1UL && lvl < SKIP_MAXLEVEL {
    lvl = lvl + 1
  }
  lvl
}

///|
/// 查找。
pub fn[K : Compare, V] SkipList::get(self : SkipList[K, V], key : K) -> V? {
  let mut cur = self.head
  let mut i = self.level - 1
  while i >= 0 {
    while true {
      match cur {
        Some(node) =>
          match node.forward[i] {
            Some(nxt) =>
              if nxt.key.compare(key) < 0 {
                cur = Some(nxt)
              } else {
                break
              }
            None => break
          }
        None => break
      }
    }
    i = i - 1
  }
  // cur 停在最底层最后一个 < key 的节点（或 head）；其 forward[0] 可能命中。
  let start = self.forward_at(cur, 0)
  match start {
    Some(nxt) => if nxt.key.compare(key) == 0 { Some(nxt.value) } else { None }
    None => None
  }
}

///|
/// 是否含键。
pub fn[K : Compare, V] SkipList::contains(
  self : SkipList[K, V],
  key : K,
) -> Bool {
  self.get(key) is Some(_)
}

///|
/// 收集各层「最后一个 < key」的前驱节点（None 表示该层从 head 起）。
fn[K : Compare, V] SkipList::find_update(
  self : SkipList[K, V],
  key : K,
) -> Array[SkipNode[K, V]?] {
  let update : Array[SkipNode[K, V]?] = Array::make(SKIP_MAXLEVEL, None)
  let mut cur = self.head
  let mut i = self.level - 1
  while i >= 0 {
    while true {
      let nxt = match cur {
        Some(node) => node.forward[i]
        None => None
      }
      match nxt {
        Some(n) => if n.key.compare(key) < 0 { cur = Some(n) } else { break }
        None => break
      }
    }
    update[i] = cur
    i = i - 1
  }
  update
}

///|
/// 取某节点/头在第 i 层的后继。
fn[K, V] SkipList::forward_at(
  self : SkipList[K, V],
  node : SkipNode[K, V]?,
  i : Int,
) -> SkipNode[K, V]? {
  match node {
    Some(n) => n.forward[i]
    None =>
      match self.head {
        Some(h) => h.forward[i]
        None => None
      }
  }
}

///|
/// 设置某节点/头在第 i 层的后继。
fn[K, V] SkipList::set_forward(
  self : SkipList[K, V],
  node : SkipNode[K, V]?,
  i : Int,
  target : SkipNode[K, V]?,
) -> Unit {
  match node {
    Some(n) => n.forward[i] = target
    None =>
      match self.head {
        Some(h) => h.forward[i] = target
        None => ()
      }
  }
}

///|
/// 确保 head 哨兵存在。
fn[K, V] SkipList::ensure_head(
  self : SkipList[K, V],
  sample_key : K,
  sample_value : V,
) -> Unit {
  match self.head {
    Some(_) => ()
    None =>
      self.head = Some({
        key: sample_key,
        value: sample_value,
        forward: Array::make(SKIP_MAXLEVEL, None),
      })
  }
}

///|
/// 插入/更新；返回旧值（若键已存在）。
pub fn[K : Compare, V] SkipList::insert(
  self : SkipList[K, V],
  key : K,
  value : V,
) -> V? {
  self.ensure_head(key, value)
  let update = self.find_update(key)
  // 命中则更新。
  let cand = self.forward_at(update[0], 0)
  match cand {
    Some(n) =>
      if n.key.compare(key) == 0 {
        let old = n.value
        n.value = value
        return Some(old)
      }
    None => ()
  }
  let lvl = self.random_level()
  if lvl > self.level {
    for i in self.level..<lvl {
      update[i] = self.head // 新层从 head 起
    }
    self.level = lvl
  }
  let node : SkipNode[K, V] = { key, value, forward: Array::make(lvl, None) }
  for i in 0..<lvl {
    node.forward[i] = self.forward_at(update[i], i)
    self.set_forward(update[i], i, Some(node))
  }
  self.count = self.count + 1
  None
}

///|
/// 删除；返回旧值（若存在）。
pub fn[K : Compare, V] SkipList::remove(self : SkipList[K, V], key : K) -> V? {
  if self.head is None {
    return None
  }
  let update = self.find_update(key)
  let target = self.forward_at(update[0], 0)
  match target {
    Some(n) =>
      if n.key.compare(key) != 0 {
        return None
      } else {
        for i in 0..<self.level {
          if self.forward_at(update[i], i) is Some(x) && physical_eq(x, n) {
            self.set_forward(update[i], i, n.forward[i])
          }
        }
        // 回收空顶层。
        while self.level > 0 &&
              (match self.head {
                Some(h) => h.forward[self.level - 1] is None
                None => true
              }) {
          self.level = self.level - 1
        }
        self.count = self.count - 1
        Some(n.value)
      }
    None => None
  }
}

///|
/// 节点物理同一判定（比较键——键在表内唯一，等价于身份）。
fn[K : Compare, V] physical_eq(a : SkipNode[K, V], b : SkipNode[K, V]) -> Bool {
  a.key.compare(b.key) == 0
}

///|
/// 半开区间 [lo, hi) 升序扫描。
pub fn[K : Compare, V] SkipList::range(
  self : SkipList[K, V],
  lo : K,
  hi : K,
) -> Array[(K, V)] {
  let out : Array[(K, V)] = []
  let update = self.find_update(lo)
  let mut cur = self.forward_at(update[0], 0)
  while true {
    match cur {
      Some(n) =>
        if n.key.compare(hi) < 0 {
          out.push((n.key, n.value))
          cur = n.forward[0]
        } else {
          break
        }
      None => break
    }
  }
  out
}

///|
/// 升序全量导出。
pub fn[K, V] SkipList::to_array(self : SkipList[K, V]) -> Array[(K, V)] {
  let out : Array[(K, V)] = []
  let mut cur = match self.head {
    Some(h) => h.forward[0]
    None => None
  }
  while true {
    match cur {
      Some(n) => {
        out.push((n.key, n.value))
        cur = n.forward[0]
      }
      None => break
    }
  }
  out
}
