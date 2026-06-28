// prop_liveness_test.mbt —— Property 6：活跃性不动点正确（任务 1.3）。
//
// Feature: codegen-infra, Property 6: 活跃性不动点正确
// **Validates: Requirements 4.1, 4.5**
//
// 性质：对任意带唯一入口的随机 CFG，`analyze_liveness` 的结果为数据流方程的
// 不动点——再施加一次传递方程（`live_out=⋃后继live_in`、
// `live_in=use∪(live_out\def)`，即 `liveness_step`）不改变任何块的
// live-in / live-out。复用 @infra_pbt.holds_for_all（100 次迭代）。

///|
/// 两个（已按 id 升序规范化的）`Var` 数组是否相等。
fn t_var_arr_eq(a : Array[Var], b : Array[Var]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i].id != b[i].id {
      return false
    }
  }
  true
}

///|
/// 两个活跃性结果在所有块的 live-in / live-out 上是否完全一致。
fn t_liveness_eq(
  blocks : Array[BasicBlock],
  a : LivenessResult,
  b : LivenessResult,
) -> Bool {
  for blk in blocks {
    if !t_var_arr_eq(
        a.live_in.get(blk.label).unwrap_or([]),
        b.live_in.get(blk.label).unwrap_or([]),
      ) {
      return false
    }
    if !t_var_arr_eq(
        a.live_out.get(blk.label).unwrap_or([]),
        b.live_out.get(blk.label).unwrap_or([]),
      ) {
      return false
    }
  }
  true
}

///|
/// Feature: codegen-infra, Property 6: 活跃性不动点正确
/// **Validates: Requirements 4.1, 4.5**
test "Feature: codegen-infra, Property 6: liveness is a dataflow fixpoint" {
  let ok = @infra_pbt.holds_for_all(
    gen_cfg(),
    fn(blocks) {
      let live = analyze_liveness(blocks)
      let again = liveness_step(blocks, live)
      t_liveness_eq(blocks, live, again)
    },
    iters=100,
  )
  assert_true(ok)
}
