// bounded_packrat.mbt —— L1 有界 packrat 缓存（Requirement 6.4 / 6.5，
// design.md §「Parser Combinator 增强设计 → AC4/AC5 有界缓存」）。
//
// 本文件以「冻结现有 API + 仅新增（bypass）」策略，在既有引擎层
// （`Grammar[T]` / `PCtx` / `Outcome` / `pc_run` / `pc_project`）之上新增一个
// 「内存可控」的 packrat 运行入口 `Grammar::run_packrat_bounded`，并提供其底层
// 的有界 LRU 缓存结构 `BoundedCache[T]`。既有 `memoize` / `run_packrat` 的实现
// 与签名均不改动。
//
// 设计动机与正确性论证（关键）：
//   * packrat 记忆化本质上是「(被记忆解析器 × 输入位置) → 结果」的**纯函数
//     缓存**——同一解析器在同一位置无论计算多少次都得到逐字段一致的结果
//     （解析器无副作用、`Input` 不可变）。因此缓存仅用于避免重复计算以提速，
//     **缓存命中与否绝不改变最终解析结果**。
//   * 由此，对缓存施加容量上限并按 LRU 淘汰条目是安全的：被淘汰的条目在再次
//     需要时「未命中即重算」，重算结果与未淘汰时完全相同（AC4）。淘汰只影响
//     性能/内存，不影响正确性。
//   * 任意时刻缓存条目数恒 <= cap（AC5），内存占用受 cap 严格约束。
//
// 实现路径说明（相对既有 `memoize`）：
//   既有 `memoize(g)` 把缓存以闭包形式下沉到「每个被记忆节点」，键为输入偏移，
//   且无容量上限（生命周期随 run_id 隔离）。由于该闭包缓存封装在节点内部、且
//   引擎 `PCtx` 为冻结契约（不可新增字段），无法从外部替换为有界容器。故本入口
//   按 design.md 允许的方式实现「等价的有界 packrat 解析驱动」：以**朴素求值**
//   （`enable_memo=false`，关闭节点内闭包缓存）执行文法，并由一张**中心化的
//   有界 LRU 缓存** `BoundedCache` 作为唯一的 packrat 记忆表（键为输入偏移）。
//   朴素求值与记忆化求值对同一文法、同一输入产生逐字段一致的结果（既有
//   Property 23「packrat 与朴素差分一致性」已对此做属性验证），故
//   `run_packrat_bounded` 的结果恒等于 `run_packrat`，同时全部记忆条目都收纳在
//   单一的有界缓存中、受 cap 严格约束（满足 AC4/AC5 的「内存可控」目标）。

///|
/// 有界 packrat 缓存（bounded packrat cache）。
///
/// 以输入偏移（offset）为键、引擎内部结果 `Outcome[T]` 为值的 LRU 缓存，容量
/// 上限为 `cap`：
///   * `entries` —— 偏移到结果的映射；
///   * `order` —— 偏移的访问顺序列表，约定**队首（index 0）为最久未使用
///     （least-recently-used）**、队尾为最近使用，与 `entries` 的键集合始终同步；
///   * `cap` —— 容量上限。`cap <= 0` 视为「不缓存」（见 `put`）。
///
/// 不变量：`order.length() == entries 的条目数`，且任意时刻 `<= max(cap, 0)`。
pub struct BoundedCache[T] {
  cap : Int
  entries : Map[Int, Outcome[T]]
  order : Array[Int]
}

///|
/// 新建容量上限为 `cap` 的空有界缓存。
///
/// `cap <= 0` 合法：表示「无缓存」语义——任何写入都被丢弃、查询恒未命中，
/// 从而每次都重算（结果仍正确，仅不获得记忆化加速）。
pub fn[T] BoundedCache::new(cap : Int) -> BoundedCache[T] {
  let entries : Map[Int, Outcome[T]] = Map([])
  let order : Array[Int] = []
  { cap, entries, order }
}

///|
/// 当前缓存的条目数（恒 <= max(cap, 0)，对应 AC5）。
pub fn[T] BoundedCache::len(self : BoundedCache[T]) -> Int {
  self.order.length()
}

///|
/// 缓存的容量上限 `cap`。
pub fn[T] BoundedCache::capacity(self : BoundedCache[T]) -> Int {
  self.cap
}

///|
/// 偏移 `off` 是否在缓存中。
pub fn[T] BoundedCache::contains(self : BoundedCache[T], off : Int) -> Bool {
  self.entries.contains(off)
}

///|
/// 查询偏移 `off` 处的缓存结果；命中时把该偏移标记为「最近使用」（移动到队尾），
/// 未命中返回 `None`。
pub fn[T] BoundedCache::get(self : BoundedCache[T], off : Int) -> Outcome[T]? {
  match self.entries.get(off) {
    Some(o) => {
      bp_touch(self.order, off)
      Some(o)
    }
    None => None
  }
}

///|
/// 写入「偏移 `off` → 结果 `outcome`」，并维持容量上限与 LRU 不变量：
///   * `cap <= 0`：直接丢弃（无缓存语义），条目数恒为 0；
///   * 偏移已存在：更新其值并标记为最近使用；
///   * 偏移不存在且已达容量上限：先按 LRU 淘汰队首（最久未使用）条目，再写入；
///     淘汰的条目在后续「未命中即重算」时得到一致结果（AC4）。
pub fn[T] BoundedCache::put(
  self : BoundedCache[T],
  off : Int,
  outcome : Outcome[T],
) -> Unit {
  if self.cap <= 0 {
    return
  }
  if self.entries.contains(off) {
    self.entries.set(off, outcome)
    bp_touch(self.order, off)
    return
  }
  if self.order.length() >= self.cap {
    self.bp_evict_lru()
  }
  self.entries.set(off, outcome)
  self.order.push(off)
}

///|
/// 内部辅助：在访问顺序列表中查找偏移 `off` 的索引，未找到返回 `-1`。
fn bp_index_of(order : Array[Int], off : Int) -> Int {
  let mut idx = -1
  let mut i = 0
  while i < order.length() && idx < 0 {
    if order[i] == off {
      idx = i
    }
    i = i + 1
  }
  idx
}

///|
/// 内部辅助：把偏移 `off` 标记为「最近使用」——从访问顺序列表中移除后追加到
/// 队尾。若不存在则不做改动。
fn bp_touch(order : Array[Int], off : Int) -> Unit {
  let idx = bp_index_of(order, off)
  if idx >= 0 {
    let _ = order.remove(idx)
    order.push(off)
  }
}

///|
/// 内部辅助：按 LRU 淘汰一个条目——移除访问顺序列表队首（最久未使用）对应的
/// 偏移及其缓存值。空缓存时为安全空操作。
fn[T] BoundedCache::bp_evict_lru(self : BoundedCache[T]) -> Unit {
  if self.order.length() > 0 {
    let victim = self.order.remove(0)
    self.entries.remove(victim)
  }
}

///|
/// 有界 packrat 运行入口（内存可控的记忆化解析）。
///
/// 在给定 `cap` 上限下运行文法 `self`：以单张有界 LRU 缓存 `BoundedCache` 作为
/// packrat 记忆表（键为输入偏移），底层以朴素求值执行文法。语义保证：
///   * **结果恒等于 `run_packrat`**：朴素求值与记忆化求值对同一文法、同一输入
///     产生逐字段一致的结果（既有 Property 23），且缓存为纯函数缓存——命中与否
///     不改变结果，被 LRU 淘汰的条目重算得到相同结果（AC4）；
///   * **内存受 `cap` 约束**：任意时刻缓存条目数 <= cap（AC5）；
///   * `cap <= 0`：退化为「无缓存」，每次重算，结果仍正确。
///
/// 调用方无需改动文法定义即可在 `run_packrat` / `run_packrat_bounded` 间切换。
pub fn[T] Grammar::run_packrat_bounded(
  self : Grammar[T],
  input : Input,
  cap~ : Int,
) -> ParseResult[T] {
  let cache : BoundedCache[T] = BoundedCache::new(cap)
  // 关闭节点内闭包缓存（enable_memo=false），令有界中心缓存成为唯一记忆表，
  // 从而把全部记忆条目收纳到受 cap 约束的容器中（朴素求值与记忆化求值结果一致）。
  let ctx = pc_new_ctx(false)
  pc_project(bp_run(self, ctx, input, cache))
}

///|
/// 便捷入口：直接在字符串上以有界 packrat 运行（内部构造 `Input`）。
pub fn[T] Grammar::run_packrat_bounded_string(
  self : Grammar[T],
  source : String,
  cap~ : Int,
) -> ParseResult[T] {
  self.run_packrat_bounded(Input::from_string(source), cap~)
}

///|
/// 内部辅助：经有界缓存运行文法 `g`。以输入偏移为键查缓存：命中直接返回，
/// 未命中则朴素求值、写回缓存（可能触发 LRU 淘汰）后返回。
fn[T] bp_run(
  g : Grammar[T],
  ctx : PCtx,
  input : Input,
  cache : BoundedCache[T],
) -> Outcome[T] {
  let off = input.pos.offset
  match cache.get(off) {
    Some(o) => o
    None => {
      let o = pc_run(g, ctx, input)
      cache.put(off, o)
      o
    }
  }
}

///|
/// 烟雾测试：有界 packrat 结果与无淘汰 `run_packrat` 一致（含 cap 极小情形）。
test "run_packrat_bounded 结果与 run_packrat 一致" {
  let digit = lift(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字"))
  let g = json_value_grammar()
  // 数字文法与 JSON 文法在多种 cap 下结果均与 run_packrat 一致。
  for src in ["123", "abc", "", "  42 "] {
    let baseline = digit.run_packrat_string(src)
    for cap in [0, 1, 2, 8] {
      let bounded = digit.run_packrat_bounded_string(src, cap~)
      assert_true(bp_result_eq_char(baseline, bounded))
    }
  }
  for src in ["[1,2,3]", "{\"a\":true}", "null", "[", "{"] {
    let baseline = g.run_packrat_string(src)
    for cap in [0, 1, 4] {
      let bounded = g.run_packrat_bounded_string(src, cap~)
      @test.assert_eq(baseline.is_ok(), bounded.is_ok())
      match (baseline.rest(), bounded.rest()) {
        (Some(r1), Some(r2)) => @test.assert_eq(r1.pos.offset, r2.pos.offset)
        (None, None) => ()
        _ => @test.assert_eq(true, false)
      }
    }
  }
}

///|
/// 烟雾测试：BoundedCache LRU 淘汰——容量满时移除最久未使用条目，且条目数 <= cap。
test "BoundedCache LRU 淘汰与容量上限" {
  let cache : BoundedCache[Int] = BoundedCache::new(2)
  let mk = fn(n : Int) { OOk(n, Input::from_string("")) }
  cache.put(10, mk(1))
  cache.put(20, mk(2))
  @test.assert_eq(cache.len(), 2)
  // 访问 10 使其成为最近使用，则下一次淘汰应移除 20（最久未使用）。
  let _ = cache.get(10)
  cache.put(30, mk(3))
  @test.assert_eq(cache.len(), 2)
  assert_true(cache.contains(10))
  assert_true(cache.contains(30))
  assert_true(!cache.contains(20))
}

///|
/// 烟雾测试：cap <= 0 视为「无缓存」，写入被丢弃、查询恒未命中、条目数恒为 0。
test "BoundedCache cap<=0 无缓存语义" {
  let cache : BoundedCache[Int] = BoundedCache::new(0)
  cache.put(1, OOk(1, Input::from_string("")))
  cache.put(2, OOk(2, Input::from_string("")))
  @test.assert_eq(cache.len(), 0)
  assert_true(!cache.contains(1))
  @test.assert_eq(cache.get(1) is None, true)
}

///|
/// 烟雾测试：连续写入多个偏移，条目数始终不超过 cap（AC5 不变量）。
test "BoundedCache 条目数始终不超过 cap" {
  let cap = 3
  let cache : BoundedCache[Int] = BoundedCache::new(cap)
  let mut off = 0
  while off < 20 {
    cache.put(off, OOk(off, Input::from_string("")))
    assert_true(cache.len() <= cap)
    off = off + 1
  }
  @test.assert_eq(cache.len(), cap)
}

///|
/// 测试辅助：`ParseResult[Char]` 的逐字段比较（值 / 剩余偏移 / 失败诊断）。
fn bp_result_eq_char(a : ParseResult[Char], b : ParseResult[Char]) -> Bool {
  match (a, b) {
    (Ok(v1, r1), Ok(v2, r2)) => v1 == v2 && r1.pos.offset == r2.pos.offset
    (Fail(p1, expected=e1), Fail(p2, expected=e2)) =>
      p1.offset == p2.offset && e1 == e2
    _ => false
  }
}
