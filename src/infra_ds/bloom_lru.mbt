// bloom_lru.mbt —— E5 数据结构基础设施：BloomFilter 与 LRU 缓存。
//
// paper-to-code：
// - Bloom. *Space/Time Trade-offs in Hash Coding with Allowable Errors.*
//   CACM 1970：m 位数组 + k 个独立哈希；查询无假阴性、假阳率
//   ≈ (1 - e^{-kn/m})^k；k 个哈希用 Kirsch–Mitzenmacher 双哈希
//   g_i(x) = h1(x) + i·h2(x)（*Less Hashing, Same Performance*, 2006）
//   构造，只需两次基础哈希；
// - LRU：O(1) get/put 的经典组合——哈希表定位 + 双向链表维护
//   最近使用序（同 Redis/内核页缓存的 LRU 骨架），本实现用
//   数组槽位 + prev/next 索引模拟侵入式链表，免节点分配。

///|
/// Bloom 过滤器（FNV-1a 64 位双哈希派生 k 个探针）。
pub struct BloomFilter {
  bits : Array[UInt64] // 位数组，64 位一字
  m : Int // 位数
  k : Int // 哈希个数
  mut n : Int // 已插入元素数
}

///|
/// 按预期容量与目标假阳率构造：m = ⌈-n·ln p / (ln 2)²⌉、
/// k = ⌈(m/n)·ln 2⌉（Bloom 1970 的最优参数公式，整数近似）。
pub fn BloomFilter::create(expected : Int, fp_permille : Int) -> BloomFilter {
  let n = if expected < 1 { 1 } else { expected }
  // ln p 近似：p 以千分率给出（如 10 = 1%），用查表避免浮点日志。
  // m/n = -ln p / (ln2)^2 ≈ 2.081 · log2(1/p)。
  let p = if fp_permille < 1 { 1 } else { fp_permille }
  // log2(1000/p) 的整数近似。
  let mut ratio = 1000 / p
  let mut log2 = 0
  while ratio > 1 {
    ratio = ratio / 2
    log2 = log2 + 1
  }
  let bits_per_elem = 2081 * log2 / 1000 + 1 // ≈ 2.081·log2(1/p)
  let m = n * bits_per_elem + 64
  let k = 693 * bits_per_elem / 1000 + 1 // ≈ ln2 · m/n
  let words = (m + 63) / 64
  { bits: Array::make(words, 0UL), m: words * 64, k, n: 0 }
}

///|
/// FNV-1a 64 位（基础哈希 1）。
fn bloom_h1(key : String) -> UInt64 {
  let mut h = 0xCBF29CE484222325UL
  for c in key.iter() {
    let cp = c.to_int()
    h = h ^ (cp & 0xFF).to_uint64()
    h = h * 0x100000001B3UL
    h = h ^ ((cp >> 8) & 0xFF).to_uint64()
    h = h * 0x100000001B3UL
  }
  h
}

///|
/// xorshift 混合（基础哈希 2，保证与 h1 弱相关）。
fn bloom_h2(key : String) -> UInt64 {
  let mut h = bloom_h1(key) ^ 0x9E3779B97F4A7C15UL
  h = h ^ (h >> 33)
  h = h * 0xFF51AFD7ED558CCDUL
  h = h ^ (h >> 33)
  // 双哈希步长需为奇数以遍历所有槽位。
  h | 1UL
}

///|
/// 插入元素。
pub fn BloomFilter::insert(self : BloomFilter, key : String) -> Unit {
  let h1 = bloom_h1(key)
  let h2 = bloom_h2(key)
  for i in 0..<self.k {
    let idx = ((h1 + i.to_uint64() * h2) %
    self.m.to_int64().reinterpret_as_uint64()).to_int()
    self.bits[idx / 64] = self.bits[idx / 64] | (1UL << (idx % 64))
  }
  self.n = self.n + 1
}

///|
/// 查询（可能假阳，绝无假阴）。
pub fn BloomFilter::contains(self : BloomFilter, key : String) -> Bool {
  let h1 = bloom_h1(key)
  let h2 = bloom_h2(key)
  for i in 0..<self.k {
    let idx = ((h1 + i.to_uint64() * h2) %
    self.m.to_int64().reinterpret_as_uint64()).to_int()
    if (self.bits[idx / 64] & (1UL << (idx % 64))) == 0UL {
      return false
    }
  }
  true
}

///|
/// 已插入元素计数。
pub fn BloomFilter::count(self : BloomFilter) -> Int {
  self.n
}

///|
/// LRU 缓存：哈希表定位 + 槽位数组双向链表，get/put 均摊 O(1)。
pub struct LruCache[K, V] {
  capacity : Int
  index : Map[K, Int] // key → 槽位
  keys : Array[K?]
  values : Array[V?]
  prev : Array[Int]
  next : Array[Int]
  mut head : Int // 最近使用（-1 空）
  mut tail : Int // 最久未用（-1 空）
  free : Array[Int] // 空闲槽位栈
}

///|
/// 按容量构造（capacity ≥ 1）。
pub fn[K : Eq + Hash, V] LruCache::create(capacity : Int) -> LruCache[K, V] {
  let cap = if capacity < 1 { 1 } else { capacity }
  let free : Array[Int] = []
  for i in 0..<cap {
    free.push(cap - 1 - i)
  }
  {
    capacity: cap,
    index: Map([]),
    keys: Array::make(cap, None),
    values: Array::make(cap, None),
    prev: Array::make(cap, -1),
    next: Array::make(cap, -1),
    head: -1,
    tail: -1,
    free,
  }
}

///|
/// 摘除槽位（链表内部操作）。
fn[K, V] LruCache::unlink(self : LruCache[K, V], slot : Int) -> Unit {
  let p = self.prev[slot]
  let nx = self.next[slot]
  if p != -1 {
    self.next[p] = nx
  } else {
    self.head = nx
  }
  if nx != -1 {
    self.prev[nx] = p
  } else {
    self.tail = p
  }
  self.prev[slot] = -1
  self.next[slot] = -1
}

///|
/// 插到链表头（最近使用端）。
fn[K, V] LruCache::push_front(self : LruCache[K, V], slot : Int) -> Unit {
  self.prev[slot] = -1
  self.next[slot] = self.head
  if self.head != -1 {
    self.prev[self.head] = slot
  }
  self.head = slot
  if self.tail == -1 {
    self.tail = slot
  }
}

///|
/// 查询并触摸（命中则移到最近使用端）。
pub fn[K : Eq + Hash, V] LruCache::get(self : LruCache[K, V], key : K) -> V? {
  match self.index.get(key) {
    Some(slot) => {
      self.unlink(slot)
      self.push_front(slot)
      self.values[slot]
    }
    None => None
  }
}

///|
/// 写入；容量满时淘汰最久未用条目。
pub fn[K : Eq + Hash, V] LruCache::put(
  self : LruCache[K, V],
  key : K,
  value : V,
) -> Unit {
  match self.index.get(key) {
    Some(slot) => {
      self.values[slot] = Some(value)
      self.unlink(slot)
      self.push_front(slot)
    }
    None => {
      let slot = if self.free.length() > 0 {
        self.free.unsafe_pop()
      } else {
        // 淘汰尾部（最久未用）。
        let victim = self.tail
        match self.keys[victim] {
          Some(old_key) => self.index.remove(old_key)
          None => ()
        }
        self.unlink(victim)
        victim
      }
      self.keys[slot] = Some(key)
      self.values[slot] = Some(value)
      self.index.set(key, slot)
      self.push_front(slot)
    }
  }
}

///|
/// 当前条目数。
pub fn[K, V] LruCache::size(self : LruCache[K, V]) -> Int {
  self.index.length()
}

///|
/// 缓存容量。
pub fn[K, V] LruCache::cap(self : LruCache[K, V]) -> Int {
  self.capacity
}
