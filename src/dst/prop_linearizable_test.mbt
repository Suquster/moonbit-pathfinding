// prop_linearizable_test.mbt —— Property 13：线性一致性判定可靠性（任务 14.3）。
//
// Feature: dst, Property 13: 线性一致性判定可靠性（按构造生成的可线性化历史返回
// Linearizable；按构造注入违反顺序规约的历史返回 NotLinearizable(conflict) 且
// conflict 非空）。
//
// **Validates: Requirements 7.4, 7.5**

///|
/// 生成器：(是否可线性化, 写入值 v1, 与 v1 不同的读出值 v2)。
fn p13_gen() -> @infra_pbt.Gen[(Bool, Int, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    (rng.next_bool(), rng.next_range(0, 50), rng.next_range(51, 100))
  })
}

///|
/// **Validates: Requirements 7.4, 7.5**
test "Feature: dst, Property 13: linearizability decision is reliable" {
  let ok = @infra_pbt.holds_for_all(p13_gen(), fn(t) {
    let (lin, v1, v2) = t
    let model : RegisterModel = { init: 0 }
    if lin {
      // 顺序历史：put v1 后 get 读到 v1（可线性化）。
      let h : Array[OpEvent] = [
        OpEvent::invoke(0, "put", v1, 0UL),
        OpEvent::ret(0, "put", 0, 1UL),
        OpEvent::invoke(0, "get", 0, 2UL),
        OpEvent::ret(0, "get", v1, 3UL),
      ]
      match is_linearizable(h, model) {
        Linearizable => true
        NotLinearizable(..) => false
      }
    } else {
      // put v1 后 get 读到 v2 (≠ v1)，且 get 实时晚于 put → 不可线性化。
      let h : Array[OpEvent] = [
        OpEvent::invoke(0, "put", v1, 0UL),
        OpEvent::ret(0, "put", 0, 1UL),
        OpEvent::invoke(0, "get", 0, 2UL),
        OpEvent::ret(0, "get", v2, 3UL),
      ]
      match is_linearizable(h, model) {
        NotLinearizable(conflict~) => conflict.length() > 0
        Linearizable => false
      }
    }
  })
  assert_true(ok)
}
