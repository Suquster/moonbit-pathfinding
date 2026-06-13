// left_recursion.mbt —— L1 直接左递归（direct left recursion）via seed-growing。
//
// 对应 tasks.md 任务 9.1，落地 design.md §「组件与接口 → 8. 直接左递归」。
// 论文出处：Warth et al. 2008《Packrat Parsers Can Support Left Recursion》的
// 种子增长（seed-growing）算法——以「失败种子 + 迭代增长」在 packrat 框架内
// 支持形如 `A := A op b | b` 的直接左递归而不无限递归。
//
// 范围声明（呼应 R13.6）：本实现仅承诺**直接**左递归（规则直接以自身为最左
// 符号）；间接 / 相互左递归不在 R9 范围内。

///|
/// 左递归头信息：某左递归位置当前的「种子」结果。
///
/// 增长期间该位置在 `states` 表中存在即代表「正在增长」，最左递归引用读取其
/// `seed`；增长收敛后表项的 `seed` 即最终结果（亦充当该位置的记忆缓存）。
priv struct LRState[T] {
  mut seed : Outcome[T]
}

///|
/// `left_recursive(name, body)`：定义一个直接左递归规则并以 seed-growing 求值。
///
/// `body` 接收「规则自身的引用」以书写 `A := A op b | b` 形式的产生式。算法
/// （Warth 2008，直接左递归）：
///   1. 首次在某位置 `o` 求值时，以**失败种子**占位并标记 growing，使规则体内
///      对自身的最左递归引用立即命中失败种子而不下钻（打破无限递归，R9.1）；
///   2. **迭代增长**：用当前种子作为「自身引用」的结果运行一次规则体；若新结果
///      比种子消费了更多输入则更新种子并重复，否则停止（R9.2）；
///   3. 增长收敛后返回最长匹配结果（R9.3 左结合）；
///   4. 基础情形在起始位置即无匹配时，返回携带起始位置与期望的失败且不消费
///      （R9.4）。
/// 缓存以 `run_id` 隔离，限定于单次运行。
pub fn[T] left_recursive(
  name : String,
  body : (Grammar[T]) -> Grammar[T],
) -> Grammar[T] {
  let states : Map[Int, LRState[T]] = Map([])
  let states_run : Array[Int] = [-1]
  let self_ref : Array[Grammar[T]] = []
  let g = Grammar::new(fn(ctx, input) {
    // 按 run_id 隔离缓存（R8.5 同理，服务于单次运行内的 seed 共享）。
    if states_run[0] != ctx.run_id {
      states.clear()
      states_run[0] = ctx.run_id
    }
    let o = input.pos.offset
    match states.get(o) {
      // 已在增长中（最左递归引用）或已增长完成 → 返回当前/最终种子。
      Some(st) => st.seed
      None => {
        // 在 o 处开始增长：失败种子占位。
        let st : LRState[T] = { seed: OFail(input.pos, [name], false) }
        states.set(o, st)
        let self_g = self_ref[0]
        let mut grown = false
        let mut continue_grow = true
        while continue_grow {
          let res = pc_run(body(self_g), ctx, input)
          match res {
            OOk(_, rest) => {
              let better = match st.seed {
                OOk(_, srest) => rest.pos.offset > srest.pos.offset
                OFail(_, _, _) => true
              }
              if better {
                st.seed = res
                states.set(o, st) // 写回，供下一轮自身引用读取最新种子。
                grown = true
              } else {
                continue_grow = false
              }
            }
            OFail(p, e, c) => {
              if not_grown(grown) {
                // 从未增长出成功种子 → 返回规则体的真实失败诊断（R9.4）。
                st.seed = OFail(p, e, c)
                states.set(o, st)
              }
              continue_grow = false
            }
          }
        }
        states.set(o, st)
        st.seed
      }
    }
  })
  self_ref.push(g)
  g
}

///|
/// 内部辅助：`grown` 取反（保持条件可读）。
fn not_grown(grown : Bool) -> Bool {
  !grown
}
