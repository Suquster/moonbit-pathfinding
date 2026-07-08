// match_ext_wbtest.mbt —— 任务 10.1 的极少量内联烟雾测试（smoke test，白盒）。
//
// 目的：以固定具体样例快速验证 match_ext.mbt 的核心行为（完整属性测试见任务
// 10.3）：
//   1. match 一个整数常量 → 选中对应 arm；
//   2. 解构元组并引用绑定变量；
//   3. 列表的 `cons` / `nil` 模式匹配（含返回尾列表、空列表命中 `PNil`）；
//   4. 类型不匹配返回**同含 `expected` 与 `actual`** 的 `TypeMismatch`。
// 采用白盒测试（`_wbtest.mbt`）以在同包内直接构造扩展语法树与既有 `Expr` 构造子；
// 本文件为旁路新增测试，不修改任何既有源文件。

///|
/// 测试用统一占位位置（行列对求值 / 类型无影响）。
fn mx_sp() -> Span {
  Span::{ line: 1, col: 1 }
}

///|
/// `match 1 { 1 => 10; _ => 0 }` → 求值 `VXInt(10)`，类型 `TXInt`。
test "match_ext: match int constant selects matching arm" {
  let ex = XMatch(
    XBase(EInt(1, mx_sp())),
    [(PInt(1), XBase(EInt(10, mx_sp()))), (PWild, XBase(EInt(0, mx_sp())))],
    mx_sp(),
  )
  assert_true(eval_x(ex) == VXInt(10))
  assert_true(check_x(ex) == Ok(TXInt))
}

///|
/// `match (3, true) { (a, b) => a }` → 求值 `VXInt(3)`，类型 `TXInt`。
test "match_ext: destructure tuple and reference bound variable" {
  let scrut = XBase(ETuple([EInt(3, mx_sp()), EBool(true, mx_sp())], mx_sp()))
  let ex = XMatch(
    scrut,
    [(PTuple([PVar("a"), PVar("b")]), XBase(EVar("a", mx_sp())))],
    mx_sp(),
  )
  assert_true(eval_x(ex) == VXInt(3))
  assert_true(check_x(ex) == Ok(TXInt))
}

///|
/// `match [1,2,3] { h :: t => h; [] => 0 }` → 头元素 `VXInt(1)`，类型 `TXInt`。
test "match_ext: cons pattern binds head of non-empty list" {
  let lst = XList(
    [XBase(EInt(1, mx_sp())), XBase(EInt(2, mx_sp())), XBase(EInt(3, mx_sp()))],
    mx_sp(),
  )
  let ex = XMatch(
    lst,
    [
      (PCons(PVar("h"), PVar("t")), XBase(EVar("h", mx_sp()))),
      (PNil, XBase(EInt(0, mx_sp()))),
    ],
    mx_sp(),
  )
  assert_true(eval_x(ex) == VXInt(1))
  assert_true(check_x(ex) == Ok(TXInt))
}

///|
/// `match [1,2,3] { h :: t => t; [] => [] }` → 尾列表 `VXList([2,3])`，
/// 类型 `TXList(TXInt)`。
test "match_ext: cons pattern binds tail as a list" {
  let lst = XList(
    [XBase(EInt(1, mx_sp())), XBase(EInt(2, mx_sp())), XBase(EInt(3, mx_sp()))],
    mx_sp(),
  )
  let ex = XMatch(
    lst,
    [
      (PCons(PVar("h"), PVar("t")), XBase(EVar("t", mx_sp()))),
      (PNil, XList([], mx_sp())),
    ],
    mx_sp(),
  )
  assert_true(eval_x(ex) == VXList([VXInt(2), VXInt(3)]))
  assert_true(check_x(ex) == Ok(TXList(TXInt)))
}

///|
/// `match [] { h :: t => 1; [] => 99 }` → 空列表命中 `PNil` → `VXInt(99)`。
test "match_ext: empty list matches PNil arm" {
  let lst : ExprX = XList([], mx_sp())
  let ex = XMatch(
    lst,
    [
      (PCons(PVar("h"), PVar("t")), XBase(EInt(1, mx_sp()))),
      (PNil, XBase(EInt(99, mx_sp()))),
    ],
    mx_sp(),
  )
  assert_true(eval_x(ex) == VXInt(99))
}

///|
/// 列表元素类型不一致 `[1, true]` → `TypeMismatch`，`expected=TXInt`、
/// `actual=TXBool`。
test "match_ext: list with inconsistent element types reports TypeMismatch" {
  let ex = XList(
    [XBase(EInt(1, mx_sp())), XBase(EBool(true, mx_sp()))],
    mx_sp(),
  )
  match check_x(ex) {
    Ok(t) => fail("期望 TypeMismatch，但通过了检查：\{t}")
    Err(tm) => {
      assert_true(tm.expected == TXInt)
      assert_true(tm.actual == TXBool)
    }
  }
}

///|
/// 模式与 scrutinee 类型不兼容：`match 1 { (a, b) => 0 }`（整数被元组模式匹配）
/// → `TypeMismatch`，`expected=TXInt`、`actual` 为二元元组形状。
test "match_ext: tuple pattern against int scrutinee reports TypeMismatch" {
  let ex = XMatch(
    XBase(EInt(1, mx_sp())),
    [(PTuple([PVar("a"), PVar("b")]), XBase(EInt(0, mx_sp())))],
    mx_sp(),
  )
  match check_x(ex) {
    Ok(t) => fail("期望 TypeMismatch，但通过了检查：\{t}")
    Err(tm) => {
      assert_true(tm.expected == TXInt)
      assert_true(tm.actual == TXTuple([TXInt, TXInt]))
    }
  }
}

///|
/// 手写 Show 渲染器全构造子覆盖：Pattern / TyX 的 to_string 输出稳定。
test "match_ext Show：Pattern 与 TyX 全构造子渲染" {
  let p : Pattern = PTuple([
    PWild,
    PVar("x"),
    PInt(42),
    PBool(true),
    PCons(PInt(1), PNil),
  ])
  assert_eq(
    p.to_string(),
    "PTuple([PWild, PVar(x), PInt(42), PBool(true), PCons(PInt(1), PNil)])",
  )
  let t : TyX = TXTuple([TXInt, TXBool, TXList(TXInt), TXFun(TXInt, TXBool)])
  assert_eq(
    t.to_string(),
    "TXTuple([TXInt, TXBool, TXList(TXInt), TXFun(TXInt, TXBool)])",
  )
}
