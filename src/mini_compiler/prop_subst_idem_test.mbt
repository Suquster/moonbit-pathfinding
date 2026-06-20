// prop_subst_idem_test.mbt —— 替换幂等属性测试（task 4.4，覆盖 R3.7）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 5「替换幂等」：
//
//   对任意（规范化）替换 `s` 与任意类型项 `t`，对 `t` 施加 `s` 一次与施加
//   两次结果相等：`apply_subst(s, apply_subst(s, t)) == apply_subst(s, t)`。
//
// 这是 unify.mbt（task 4.1）中「规范化替换」设计（compose / unify 产出的替换经
// `normalize` 规范化至不动点，使值域不再含定义域变量）幂等性的可执行见证。
//
// 复用约定：
//   * 复用 task 1.2 `ml_gen_test.mbt` 的（规范化）`Subst` 生成器 `ml_subst_gen`
//     —— 其把一组互异类型变量 id 映射到无变量的 ground 类型，值域不含定义域
//     变量，故替换天然幂等；以及 `Ty` 生成器 `ml_ty_gen`（含变量/函数/元组）。
//   * 因本属性同时需要 `Subst` 与 `Ty`，将两者组合为
//     `@infra_pbt.Gen[(Subst, Ty)]`：在单次采样中分别从两生成器各取一个值。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代
//     100 次（满足「每条属性测试 ≥100 迭代」基线）。
//
// 旁路新增 API（本文件只调用、不修改）：
//   apply_subst(Subst, Ty) -> Ty                  （unify.mbt，task 4.1）
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// Property 5：替换幂等
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 5: 替换幂等**
///
/// 对任意由 `ml_subst_gen` 产生的（规范化）替换 `s` 与由 `ml_ty_gen` 产生的
/// 类型项 `t`，先施加一次 `s` 得 `once`，再对 `once` 施加一次 `s` 应不改变结果，
/// 即 `apply_subst(s, apply_subst(s, t)) == apply_subst(s, t)`。复用 @infra_pbt
/// 的 `holds_for_all`，迭代 100 次。
///
/// **Validates: Requirements 3.7**
test "Feature: mini-compiler, Property 5: 替换幂等" {
  let subst_gen = ml_subst_gen()
  let ty_gen = ml_ty_gen()
  let combined : @infra_pbt.Gen[(Subst, Ty)] = @infra_pbt.Gen::new(fn(rng) {
    (subst_gen.generate(rng), ty_gen.generate(rng))
  })
  let ok = @infra_pbt.holds_for_all(
    combined,
    fn(pair) {
      let (s, t) = pair
      let once = apply_subst(s, t)
      apply_subst(s, once) == once
    },
    iters=100,
  )
  assert_true(ok)
}
