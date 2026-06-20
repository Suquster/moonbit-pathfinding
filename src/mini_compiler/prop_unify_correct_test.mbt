// prop_unify_correct_test.mbt —— 合一正确性属性测试（task 4.2，覆盖 R3.5）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 3「合一正确性」：
//
//   对任意可合一类型项对 (t1, t2)，`unify(t1, t2)` 成功，且把所得替换分别
//   施于 t1 / t2 后两者相等。
//
// 这是 unify.mbt（task 4.1，基于不可变替换 + 复合的 Algorithm W 风格合一）
// 正确性的可执行见证：合一子（mgu）一旦求出，施于两侧类型项应使其结构相等
// （即 unify 求出的替换确实是 t1、t2 的合一子）。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的可合一类型对生成器 `ml_unifiable_pair_gen`
//     —— 其以单调递增的新鲜变量计数器保证整对中每个类型变量至多出现一次，
//     故 unify 必成功且 occurs-check 必通过，恰好覆盖本属性的输入空间。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代
//     100 次（满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   unify(Ty, Ty) -> Result[Subst, Diagnostic]   （unify.mbt，task 4.1）
//   apply_subst(Subst, Ty) -> Ty                  （unify.mbt，task 4.1）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 3：合一正确性
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 3: 合一正确性**
///
/// 对任意由 `ml_unifiable_pair_gen` 产生的可合一类型项对 (t1, t2)，
/// `unify(t1, t2)` 应返回 `Ok(s)`，且 `apply_subst(s, t1) == apply_subst(s, t2)`。
/// 即合一求出的替换确为两侧类型项的合一子。复用 @infra_pbt 的 `holds_for_all`，
/// 迭代 100 次；`unify` 返回 `Err` 即视为属性破坏（谓词返回 false 使属性失败）。
///
/// **Validates: Requirements 3.5**
test "Feature: mini-compiler, Property 3: 合一正确性" {
  let ok = @infra_pbt.holds_for_all(
    ml_unifiable_pair_gen(),
    fn(pair) {
      let (t1, t2) = pair
      match unify(t1, t2) {
        Ok(s) => apply_subst(s, t1) == apply_subst(s, t2)
        Err(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
