// unify_unit_test.mbt —— 任务 4.5：合一（unification）单元测试。
//
// 目的（R3.1 / R3.2 / R3.3 / R3.4）：以一组**固定**的具体样例，逐字断言旁路
// 合一核心 `unify.mbt`（任务 4.1）的行为：
//   1. 基本类型合一（`TyInt` / `TyBool`）成功与冲突报错（`TyInt ~ TyBool`）。
//   2. 类型变量绑定：`TyVar(v) ~ t` 两个方向、`TyVar(v) ~ TyVar(v)` 不自绑定。
//   3. 函数类型合一（参数 + 结果线程化复合）与函数 vs 基本类型冲突。
//   4. occurs-check：`TyVar(v) ~ TyFun(TyVar(v), ...)` 报 `TypeError`；并直接
//      断言 `occurs`。
//   5. 元组合一（逐元素）与长度不匹配报错。
//   6. `apply_subst` / `compose` / `ftv` 基础语义。
//
// 断言风格：`Ty` 派生 `Eq` + `Show`，标量比较用 `assert_eq`；`Result` 比较用
// `assert_true(x == y)`（`Subst` 派生 `Eq`）。诊断仅断言 `kind == TypeError`。
// 通过 match + abort 助手从 `Result` 取出 `Ok` / `Err` 分支。本文件为旁路新增的
// 黑盒 `_test.mbt`，不修改任何既有源文件；`unify.mbt` 为已验证的真值来源，期望
// 值据其实际正确行为编码。

// ---------------------------------------------------------------------------
// 测试助手
// ---------------------------------------------------------------------------

///|
/// 合一并在意外失败时中止，返回所得替换。
fn uu_ok(t1 : Ty, t2 : Ty) -> Subst {
  match unify(t1, t2) {
    Ok(s) => s
    Err(d) => abort("unify 意外失败：\{d.msg}")
  }
}

///|
/// 期望合一失败：取出诊断；若意外成功则中止。
fn uu_err(t1 : Ty, t2 : Ty) -> Diagnostic {
  match unify(t1, t2) {
    Ok(_) => abort("期望 unify 失败，但成功")
    Err(d) => d
  }
}

// ---------------------------------------------------------------------------
// 1. 基本类型（R3.1）
// ---------------------------------------------------------------------------

///|
/// `TyInt ~ TyInt` → 空替换；施于任意类型项为恒等。
test "unify: TyInt ~ TyInt yields empty subst (identity)" {
  let s = uu_ok(TyInt, TyInt)
  assert_true(s == subst_empty())
  assert_eq(apply_subst(s, TyInt), TyInt)
  assert_eq(apply_subst(s, TyVar(7)), TyVar(7))
  assert_eq(apply_subst(s, TyFun(TyVar(0), TyBool)), TyFun(TyVar(0), TyBool))
}

///|
/// `TyBool ~ TyBool` → 空替换。
test "unify: TyBool ~ TyBool yields empty subst" {
  let s = uu_ok(TyBool, TyBool)
  assert_true(s == subst_empty())
}

///|
/// `TyInt ~ TyBool` → `TypeError`。
test "unify: TyInt ~ TyBool is a TypeError" {
  let d = uu_err(TyInt, TyBool)
  assert_true(d.kind == TypeError)
}

// ---------------------------------------------------------------------------
// 2. 类型变量绑定（R3.2 / R3.4）
// ---------------------------------------------------------------------------

///|
/// `TyVar(0) ~ TyInt` → 绑定，施于 `TyVar(0)` 得 `TyInt`。
test "unify: TyVar(0) ~ TyInt binds the variable" {
  let s = uu_ok(TyVar(0), TyInt)
  assert_eq(apply_subst(s, TyVar(0)), TyInt)
}

///|
/// `TyInt ~ TyVar(0)` → 同样把变量绑定到 `TyInt`（对称方向）。
test "unify: TyInt ~ TyVar(0) binds the variable (symmetric)" {
  let s = uu_ok(TyInt, TyVar(0))
  assert_eq(apply_subst(s, TyVar(0)), TyInt)
}

///|
/// `TyVar(0) ~ TyVar(0)` → 空替换（不自绑定）。
test "unify: TyVar(0) ~ TyVar(0) yields empty subst (no self-binding)" {
  let s = uu_ok(TyVar(0), TyVar(0))
  assert_true(s == subst_empty())
}

///|
/// `TyVar(0) ~ TyVar(1)` → 把 0 绑定到变量 1。
test "unify: TyVar(0) ~ TyVar(1) binds one to the other" {
  let s = uu_ok(TyVar(0), TyVar(1))
  assert_eq(apply_subst(s, TyVar(0)), TyVar(1))
}

// ---------------------------------------------------------------------------
// 3. 函数类型（R3.3）
// ---------------------------------------------------------------------------

///|
/// `(a -> b) ~ (Int -> Bool)` → a↦Int, b↦Bool。
test "unify: function type binds both parameter and result vars" {
  let s = uu_ok(TyFun(TyVar(0), TyVar(1)), TyFun(TyInt, TyBool))
  assert_eq(apply_subst(s, TyVar(0)), TyInt)
  assert_eq(apply_subst(s, TyVar(1)), TyBool)
}

///|
/// 嵌套函数类型 + 变量在参数与结果间共享：
/// `(a -> (a -> b)) ~ (Int -> (Int -> Bool))` → a↦Int, b↦Bool。
test "unify: nested function type threads shared variable" {
  let lhs : Ty = TyFun(TyVar(0), TyFun(TyVar(0), TyVar(1)))
  let rhs : Ty = TyFun(TyInt, TyFun(TyInt, TyBool))
  let s = uu_ok(lhs, rhs)
  assert_eq(apply_subst(s, TyVar(0)), TyInt)
  assert_eq(apply_subst(s, TyVar(1)), TyBool)
  assert_eq(apply_subst(s, lhs), rhs)
}

///|
/// 参数侧冲突使整体合一失败：`(Int -> a) ~ (Bool -> Int)` → `TypeError`。
test "unify: function parameter mismatch is a TypeError" {
  let d = uu_err(TyFun(TyInt, TyVar(0)), TyFun(TyBool, TyInt))
  assert_true(d.kind == TypeError)
}

///|
/// 函数 vs 基本类型：`(Int -> Int) ~ Int` → `TypeError`。
test "unify: function vs base type is a TypeError" {
  let d = uu_err(TyFun(TyInt, TyInt), TyInt)
  assert_true(d.kind == TypeError)
}

// ---------------------------------------------------------------------------
// 4. occurs-check（R3.2）
// ---------------------------------------------------------------------------

///|
/// `TyVar(0) ~ (TyVar(0) -> TyInt)` → occurs-check 失败 `TypeError`。
test "unify: occurs check rejects infinite type" {
  let d = uu_err(TyVar(0), TyFun(TyVar(0), TyInt))
  assert_true(d.kind == TypeError)
}

///|
/// 对称方向：`(TyVar(0) -> TyInt) ~ TyVar(0)` 同样被 occurs-check 拒绝。
test "unify: occurs check rejects infinite type (symmetric)" {
  let d = uu_err(TyFun(TyVar(0), TyInt), TyVar(0))
  assert_true(d.kind == TypeError)
}

///|
/// `occurs` 直接断言：变量出现于函数类型为真，不出现于基本类型为假。
test "occurs: detects presence and absence of a variable" {
  assert_eq(occurs(0, TyFun(TyVar(0), TyInt)), true)
  assert_eq(occurs(1, TyInt), false)
  assert_eq(occurs(1, TyFun(TyVar(0), TyTuple([TyVar(1), TyInt]))), true)
  assert_eq(occurs(2, TyFun(TyVar(0), TyTuple([TyVar(1), TyInt]))), false)
}

// ---------------------------------------------------------------------------
// 5. 元组（R3.1 / R3.3）
// ---------------------------------------------------------------------------

///|
/// 逐元素合一：`(a, Bool) ~ (Int, b)` → a↦Int, b↦Bool。
test "unify: tuple unifies element-wise" {
  let s = uu_ok(TyTuple([TyVar(0), TyBool]), TyTuple([TyInt, TyVar(1)]))
  assert_eq(apply_subst(s, TyVar(0)), TyInt)
  assert_eq(apply_subst(s, TyVar(1)), TyBool)
}

///|
/// 元组长度不匹配：`(Int) ~ (Int, Int)` → `TypeError`。
test "unify: tuple length mismatch is a TypeError" {
  let d = uu_err(TyTuple([TyInt]), TyTuple([TyInt, TyInt]))
  assert_true(d.kind == TypeError)
}

///|
/// 元组元素冲突：`(Int, Bool) ~ (Int, Int)` → `TypeError`。
test "unify: tuple element conflict is a TypeError" {
  let d = uu_err(TyTuple([TyInt, TyBool]), TyTuple([TyInt, TyInt]))
  assert_true(d.kind == TypeError)
}

// ---------------------------------------------------------------------------
// 6. apply_subst / compose / ftv 基础语义（R3.4）
// ---------------------------------------------------------------------------

///|
/// `apply_subst` 递归替换函数类型中两处同一变量。
test "apply_subst: replaces all occurrences in a function type" {
  assert_eq(
    apply_subst(subst_single(0, TyInt), TyFun(TyVar(0), TyVar(0))),
    TyFun(TyInt, TyInt),
  )
}

///|
/// `apply_subst` 对元组递归下降。
test "apply_subst: descends into tuples" {
  assert_eq(
    apply_subst(subst_single(1, TyBool), TyTuple([TyVar(1), TyInt, TyVar(2)])),
    TyTuple([TyBool, TyInt, TyVar(2)]),
  )
}

///|
/// `compose` 行为如同顺序施加：`compose(s1, s2)` = 先施 s2 再施 s1。
/// 此处 s2 = {0 ↦ TyVar(1)}，s1 = {1 ↦ TyInt}，合成后 0 ↦ TyInt、1 ↦ TyInt。
test "compose: behaves like sequential application" {
  let s2 = subst_single(0, TyVar(1))
  let s1 = subst_single(1, TyInt)
  let c = compose(s1, s2)
  assert_eq(apply_subst(c, TyVar(0)), TyInt)
  assert_eq(apply_subst(c, TyVar(1)), TyInt)
}

///|
/// `ftv` 收集函数 / 元组中的自由类型变量。
test "ftv: collects free type variables" {
  let vs = ftv(TyFun(TyVar(0), TyTuple([TyVar(1), TyInt])))
  assert_eq(vs.contains(0), true)
  assert_eq(vs.contains(1), true)
  assert_eq(vs.contains(2), false)
}

///|
/// `ftv` 对无变量的基本类型为空。
test "ftv: empty for base types" {
  assert_eq(ftv(TyInt).is_empty(), true)
  assert_eq(ftv(TyBool).is_empty(), true)
}
