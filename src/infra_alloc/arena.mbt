// arena.mbt —— E3 分配基础设施：bump/region arena（批量释放型）。
//
// 对标 Rust typed-arena / bumpalo 与游戏引擎 per-frame arena：对象顺序
// bump 进连续存储，句柄为稠密下标（0..n-1），单次 `reset` O(1) 批量释放
// 整代对象并保留底层容量——稳态（如逐帧/逐请求）工作负载下每代分配数
// 归零：不重建底层数组、不逐对象释放。
//
// 与 Slab（slab.mbt）互补：Slab 面向长短寿命混杂、逐对象 free 的 churn
// 场景；Arena 面向「同代同生共死」的批量场景（编译器 AST、每帧临时图、
// 请求作用域对象），bump 分配 + O(1) 整代回收更快且句柄稠密（可直接做
// 并行数组/SoA 索引）。
//
// 对外 API：Arena::new / alloc / get / set / len / capacity / reset / iter。

///|
/// bump arena：稠密下标句柄，reset O(1) 批量释放（保留容量）。
pub struct Arena[T] {
  slots : Array[T]
  mut live : Int
}

///|
/// 空 arena。
pub fn[T] Arena::new() -> Arena[T] {
  { slots: [], live: 0 }
}

///|
/// 当前代存活对象数。
pub fn[T] Arena::len(self : Arena[T]) -> Int {
  self.live
}

///|
/// 底层容量（跨代保留）。
pub fn[T] Arena::capacity(self : Arena[T]) -> Int {
  self.slots.length()
}

///|
/// bump 分配：返回稠密下标句柄。容量足够时零分配（覆写保留槽位）。
pub fn[T] Arena::alloc(self : Arena[T], value : T) -> Int {
  let id = self.live
  if id < self.slots.length() {
    self.slots[id] = value
  } else {
    self.slots.push(value)
  }
  self.live = id + 1
  id
}

///|
/// 读句柄（当前代内有效；越界返回 None）。O(1)。
pub fn[T] Arena::get(self : Arena[T], id : Int) -> T? {
  if id < 0 || id >= self.live {
    None
  } else {
    Some(self.slots[id])
  }
}

///|
/// 写句柄（当前代内有效）。成功返回 true。O(1)。
pub fn[T] Arena::set(self : Arena[T], id : Int, value : T) -> Bool {
  if id < 0 || id >= self.live {
    false
  } else {
    self.slots[id] = value
    true
  }
}

///|
/// O(1) 批量释放当前代全部对象；底层容量保留供下一代复用。
pub fn[T] Arena::reset(self : Arena[T]) -> Unit {
  self.live = 0
}

///|
/// 遍历当前代 (id, value)。
pub fn[T] Arena::iter(self : Arena[T]) -> Array[(Int, T)] {
  let out : Array[(Int, T)] = []
  for i in 0..<self.live {
    out.push((i, self.slots[i]))
  }
  out
}
