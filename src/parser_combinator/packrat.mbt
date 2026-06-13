// packrat.mbt —— L1 packrat 记忆化（packrat memoization）。
//
// 对应 tasks.md 任务 8.1，落地 design.md §「组件与接口 → 7. packrat 记忆化」。
// 论文出处：PEG 有序选择与 packrat 记忆化源自 Ford 2002《Parsing Expression
// Grammars》/ packrat 论文——对「被记忆解析器 × 输入位置」的结果缓存，使每个
// 解析器在每个位置至多计算一次，从而把回溯型解析的最坏复杂度降为线性。
//
// 实现说明（相对 design.md 的类型安全特化）：design.md 设想一张以
// `MemoKey{node_id, offset}` 为键的全局 `ctx.memo`。由于 MoonBit 是强类型语言、
// 不同被记忆解析器产出类型 `T` 各异，无法把异构的 `Outcome[T]` 统一塞进单张
// 表，故本实现把缓存**下沉为 per-node 的类型化缓存**（`Map[Int, Outcome[T]]`，
// 键为输入偏移），并以 `run_id` 把缓存生命周期限定于单次运行——观察行为与
// design.md 完全一致（每位置至多算一次、缓存随运行新建/释放、不同输入互不
// 污染），且 `node_id` 退化为「闭包身份」从而天然不影响解析结果。

///|
/// `memoize(g)`：把富解析器 `g` 标记为可记忆。
///
///   * 在 `run_naive`（`enable_memo=false`）下：不缓存，直接求值（朴素参照，
///     R8.4 入口选择）。
///   * 在 `run_packrat`（`enable_memo=true`）下：以输入偏移为键缓存 `g` 在该
///     位置的求值结果——首次未命中则求值并写回，后续相同位置命中返回逐字段
///     一致的缓存结果（R8.1 每位置至多算一次、R8.2 一致返回）。
///   * 缓存以 `run_id` 隔离：进入新的一次运行（run_id 改变）时清空旧缓存，
///     从而把缓存生命周期限定于单次运行，不同输入互不污染（R8.5）。
pub fn[T] memoize(g : Grammar[T]) -> Grammar[T] {
  let cache : Map[Int, Outcome[T]] = Map([])
  let cache_run : Array[Int] = [-1]
  Grammar::new(fn(ctx, input) {
    if ctx.enable_memo {
      // run_id 改变 → 缓存属于上一次运行，清空以隔离（R8.5）。
      if cache_run[0] != ctx.run_id {
        cache.clear()
        cache_run[0] = ctx.run_id
      }
      let off = input.pos.offset
      match cache.get(off) {
        Some(o) => o
        None => {
          let o = pc_run(g, ctx, input)
          cache.set(off, o)
          o
        }
      }
    } else {
      // 朴素模式：不记忆，直接求值。
      pc_run(g, ctx, input)
    }
  })
}
