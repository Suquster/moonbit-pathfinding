///|
/// 基数堆（radix heap，Ahuja–Mehlhorn–Orlin–Tarjan 1990）：单调优先
/// 队列，键为编码 Int64（(优先级 << 21) | node），要求 push 的键
/// ≥ 最近一次 pop 的键（Dijkstra / 一致启发式 A* 天然满足）。桶 i
/// 存与 `last` 最高相异位为 i-1 的键；pop 摊还 O(64)，push O(1)，
/// 免比较下滤，大规模稀疏图上顺序访存优于二叉/四叉堆。
struct RadixHeap {
  bkt : Array[Array[Int64]]
  mut last : Int64
  mut len : Int
}

///|
fn RadixHeap::new() -> RadixHeap {
  let bkt : Array[Array[Int64]] = []
  for _ in 0..<65 {
    bkt.push([])
  }
  { bkt, last: 0L, len: 0 }
}

///|
/// 清空并重置基准键（每查询调用一次；键单调不减于 base）。
fn RadixHeap::reset(self : RadixHeap, base : Int64) -> Unit {
  if self.len > 0 {
    for i in 0..<65 {
      self.bkt[i].clear()
    }
  }
  self.last = base
  self.len = 0
}

///|
fn RadixHeap::push(self : RadixHeap, key : Int64) -> Unit {
  self.bkt[64 - (key ^ self.last).clz()].push(key)
  self.len = self.len + 1
}

///|
/// 使桶 0 非空（要求 len > 0）：找最低非空桶，取其最小键为新
/// `last`，桶内键按与新 last 的最高相异位重散列到更低桶。
fn RadixHeap::ensure_min(self : RadixHeap) -> Unit {
  if self.bkt[0].length() > 0 {
    return
  }
  let mut i = 1
  while self.bkt[i].length() == 0 {
    i = i + 1
  }
  let b = self.bkt[i]
  let mut mn = b[0]
  for j = 1; j < b.length(); j = j + 1 {
    if b[j] < mn {
      mn = b[j]
    }
  }
  self.last = mn
  for j = 0; j < b.length(); j = j + 1 {
    let e = b[j]
    self.bkt[64 - (e ^ mn).clz()].push(e)
  }
  b.clear()
}

///|
/// 当前最小键（要求 len > 0）。
fn RadixHeap::peek(self : RadixHeap) -> Int64 {
  self.ensure_min()
  self.last
}

///|
/// 弹出最小键（要求 len > 0）。
fn RadixHeap::pop(self : RadixHeap) -> Int64 {
  self.ensure_min()
  self.len = self.len - 1
  let b = self.bkt[0]
  b.unsafe_pop()
}
