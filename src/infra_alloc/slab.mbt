// slab.mbt —— E3 内存/分配基础设施：slab 分配器 + 分代句柄槽位映射
// （对标 Rust 生态 `slab` / `slotmap` crate）。
//
// 设计：连续槽位数组 + 侵入式空闲链（free list）。alloc 从空闲链头取槽
// O(1)，free 将槽挂回链头 O(1)，访问按索引 O(1)——彻底消除逐对象分配与
// 键式查找。每个槽携带 32 位「代数」（generation）：释放时代数 +1，句柄
// `SlabKey = (index, generation)` 在代数不匹配时访问返回 None——以常数
// 代价在 GC 语言里模拟 use-after-free 检测（slotmap 的 versioned key 语义）。
//
// 适用：运行时热路径中生命周期短、churn 高的对象（调度器任务、定时器
// 表项、图算法工作区节点），把「每操作一次分配」摊薄为「容量增长时
// 偶发分配」。
//
// 对外 API：SlabKey / Slab::new / with_capacity / len / capacity /
// alloc / get / set / free / contains / clear / iter_live。

///|
/// 分代句柄：index 定位槽位，generation 防悬垂访问。
pub struct SlabKey {
  index : Int
  generation : Int
} derive(Eq, Debug)

///|
struct Slot[T] {
  mut value : T?
  mut generation : Int
  /// 空闲时指向下一空闲槽（-1 表示链尾）；占用时无意义。
  mut next_free : Int
}

///|
/// slab 分配器：O(1) alloc/free/get，容量按需倍增。
pub struct Slab[T] {
  slots : Array[Slot[T]]
  mut free_head : Int
  mut live : Int
}

///|
/// 空 slab。
pub fn[T] Slab::new() -> Slab[T] {
  { slots: [], free_head: -1, live: 0 }
}

///|
/// 预留 n 个槽位（避免热路径中的增长分配）。
pub fn[T] Slab::with_capacity(n : Int) -> Slab[T] {
  let s : Slab[T] = Slab::new()
  s.reserve(n)
  s
}

///|
/// 追加 n 个空闲槽位。
pub fn[T] Slab::reserve(self : Slab[T], n : Int) -> Unit {
  for _ in 0..<n {
    let idx = self.slots.length()
    self.slots.push({ value: None, generation: 0, next_free: self.free_head })
    self.free_head = idx
  }
}

///|
/// 存活对象数。
pub fn[T] Slab::len(self : Slab[T]) -> Int {
  self.live
}

///|
/// 总槽位数。
pub fn[T] Slab::capacity(self : Slab[T]) -> Int {
  self.slots.length()
}

///|
/// 分配槽位存入 value，返回分代句柄。摊销 O(1)。
pub fn[T] Slab::alloc(self : Slab[T], value : T) -> SlabKey {
  if self.free_head < 0 {
    // 容量倍增（至少 8），保持摊销 O(1)。
    let grow = if self.slots.length() < 8 { 8 } else { self.slots.length() }
    self.reserve(grow)
  }
  let idx = self.free_head
  let slot = self.slots[idx]
  self.free_head = slot.next_free
  slot.value = Some(value)
  self.live = self.live + 1
  { index: idx, generation: slot.generation }
}

///|
/// 按句柄读取；句柄已失效（已释放/代数不符）返回 None。O(1)。
pub fn[T] Slab::get(self : Slab[T], key : SlabKey) -> T? {
  if key.index < 0 || key.index >= self.slots.length() {
    return None
  }
  let slot = self.slots[key.index]
  if slot.generation != key.generation {
    return None
  }
  slot.value
}

///|
/// 按句柄改写；成功返回 true，句柄失效返回 false。O(1)。
pub fn[T] Slab::set(self : Slab[T], key : SlabKey, value : T) -> Bool {
  if key.index < 0 || key.index >= self.slots.length() {
    return false
  }
  let slot = self.slots[key.index]
  if slot.generation != key.generation || slot.value is None {
    return false
  }
  slot.value = Some(value)
  true
}

///|
/// 句柄是否仍存活。O(1)。
pub fn[T] Slab::contains(self : Slab[T], key : SlabKey) -> Bool {
  self.get(key) is Some(_)
}

///|
/// 释放句柄对应对象；返回被释放值（句柄失效返回 None）。O(1)。
/// 释放后代数 +1，旧句柄永久失效。
pub fn[T] Slab::free(self : Slab[T], key : SlabKey) -> T? {
  if key.index < 0 || key.index >= self.slots.length() {
    return None
  }
  let slot = self.slots[key.index]
  if slot.generation != key.generation {
    return None
  }
  match slot.value {
    None => None
    Some(v) => {
      slot.value = None
      slot.generation = slot.generation + 1
      slot.next_free = self.free_head
      self.free_head = key.index
      self.live = self.live - 1
      Some(v)
    }
  }
}

///|
/// 释放全部存活对象（代数各 +1，容量保留）。O(capacity)。
pub fn[T] Slab::clear(self : Slab[T]) -> Unit {
  self.free_head = -1
  for idx in 0..<self.slots.length() {
    let slot = self.slots[idx]
    if slot.value is Some(_) {
      slot.value = None
      slot.generation = slot.generation + 1
    }
    slot.next_free = self.free_head
    self.free_head = idx
  }
  self.live = 0
}

///|
/// 遍历全部存活 (key, value)。O(capacity)。
pub fn[T] Slab::iter_live(self : Slab[T]) -> Array[(SlabKey, T)] {
  let out : Array[(SlabKey, T)] = []
  for idx in 0..<self.slots.length() {
    let slot = self.slots[idx]
    match slot.value {
      Some(v) => out.push(({ index: idx, generation: slot.generation }, v))
      None => ()
    }
  }
  out
}
