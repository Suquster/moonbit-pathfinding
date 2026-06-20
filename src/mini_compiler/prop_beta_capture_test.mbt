// prop_beta_capture_test.mbt —— 捕获避免替换属性测试（task 10.4，覆盖 R7.6）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 13「捕获避免替换正确」：
//
//   对任意**含字面 `lambda` 应用**（即至少含一个 `(λx. body) arg` redex）的良
//   类型闭合 `Expr` `e`，启用 beta 化简后求值结果与化简前相等：
//     eval_ml(infer(beta_reduce(e))) == eval_ml(infer(e))。
//
// 形式化说明：
//   * optimize.mbt（task 10.1）的 `beta_reduce` 对字面 lambda 的应用做**捕获
//     避免替换** `body[x ↦ arg]`：下降至绑定子（`ELam` / `ELet` / `ELetRec`）时
//     若绑定名 `y` 自由出现于 `arg` 且 `y != x`，则先对该绑定子做 **alpha 重命名**
//     到新鲜名，避免 `arg` 的自由变量被意外捕获。`eval_ml` 采用环境闭包（词法
//     作用域），故化简前的求值即为基准；beta 化简必须保持此结果。
//   * MiniML 是**纯**语言且 `eval_ml` 是**全函数**（除零=0、变量必有绑定），故
//     beta 化简（一种语义保持的求值前展开）不改变可观察结果。
//   * 本文件需要**含 lambda 应用**的良类型闭合 `Expr`。task 1.2 的通用生成器
//     `ml_well_typed_expr_gen` 保守地**不**产生 lambda / 应用，故本文件实现一个
//     **本地生成器** `beta_redex_gen`，专门产出闭合、良类型（顶层 Int）且至少
//     含一个字面 `(fun x -> body) arg` redex 的表达式（含高阶与捕获压力形态）。
//
// 复用约定：
//   * 复用 task 10.1 `optimize.mbt` 的 `beta_reduce`、task 5.1 `infer.mbt` 的
//     `infer`、task 7.1 `ml_eval.mbt` 的 `eval_ml`。
//   * 复用 task 1.2 `ml_gen_test.mbt` 的 `ml_pick_binop`（同包黑盒测试符号）。
//   * 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all`，迭代 100 次。
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// 本地生成器：含字面 lambda 应用的良类型闭合 Expr
// ---------------------------------------------------------------------------

///|
/// 哨兵 span（与 of_minilet 一致）：本地生成器节点统一用 `Span{line:0,col:0}`。
fn beta_sp() -> Span {
  Span::{ line: 0, col: 0 }
}

///|
/// 采样一个**闭合**、目标类型为 Int 的小表达式：仅引用作用域 `scope`（均为 Int
/// 类型的 lambda 形参）中的变量，或整数字面量，或二者的算术组合。保证闭合且
/// 良类型（Int）。
fn beta_int_expr(
  rng : @infra_pbt.Rng,
  scope : Array[String],
  depth : Int,
) -> Expr {
  let s = beta_sp()
  if depth <= 0 {
    if scope.length() > 0 && rng.next_bool() {
      EVar(scope[rng.next_below(scope.length())], s)
    } else {
      EInt(rng.next_range(0, 100), s)
    }
  } else {
    match rng.next_below(3) {
      0 =>
        if scope.length() > 0 && rng.next_bool() {
          EVar(scope[rng.next_below(scope.length())], s)
        } else {
          EInt(rng.next_range(0, 100), s)
        }
      _ =>
        EArith(
          ml_pick_binop(rng),
          beta_int_expr(rng, scope, depth - 1),
          beta_int_expr(rng, scope, depth - 1),
          s,
        )
    }
  }
}

///|
/// 采样一个闭合、良类型（顶层 Int）且**至少含一个字面 `(fun x -> body) arg`
/// redex** 的表达式。随机在四种形态间选择（含高阶与捕获压力形态），全部保证
/// 闭合且 `infer` 可成功推断为 Int。
fn beta_redex_at(rng : @infra_pbt.Rng, depth : Int) -> Expr {
  let s = beta_sp()
  match rng.next_below(4) {
    // 形态 A：`(fun x -> int_expr[x]) int_expr[]` —— body 可能用到 x。
    0 => {
      let body = beta_int_expr(rng, ["x"], depth)
      let arg = beta_int_expr(rng, [], depth)
      EApp(ELam("x", body, s), arg, s)
    }
    // 形态 B：高阶 `(fun f -> f int_arg) (fun x -> int_expr[x])` —— 实参本身是
    // lambda，子结构对捕获避免替换施加压力。
    1 => {
      let int_arg = beta_int_expr(rng, [], depth)
      let lam_body : Expr = EApp(EVar("f", s), int_arg, s)
      let fx = beta_int_expr(rng, ["x"], depth)
      EApp(ELam("f", lam_body, s), ELam("x", fx, s), s)
    }
    // 形态 C：柯里化 `((fun x -> fun y -> x op y) int1) int2` —— 嵌套 lambda，
    // 朴素替换可能误捕获。
    2 => {
      let op = ml_pick_binop(rng)
      let inner : Expr = ELam("y", EArith(op, EVar("x", s), EVar("y", s), s), s)
      let curried : Expr = ELam("x", inner, s)
      let i1 = beta_int_expr(rng, [], depth)
      let i2 = beta_int_expr(rng, [], depth)
      EApp(EApp(curried, i1, s), i2, s)
    }
    // 形态 D：捕获压力（经典反例）
    //   `(fun y -> ((fun x -> (fun y -> x + y)) y) someInt) outArg`
    // 内层 redex `(fun x -> (fun y -> x + y)) y`：实参 `y` 自由引用外层绑定 y，
    // body `fun y -> x + y` 的形参亦名 `y`。朴素替换会把外层 y 捕获，捕获避免
    // 替换必须对内层 y 做 alpha 重命名。整体闭合且为 Int。
    _ => {
      let inner_lam : Expr = ELam(
        "y",
        EArith(Add, EVar("x", s), EVar("y", s), s),
        s,
      )
      let x_lam : Expr = ELam("x", inner_lam, s)
      let applied_to_y : Expr = EApp(x_lam, EVar("y", s), s)
      let some_int = beta_int_expr(rng, ["y"], depth)
      let inner : Expr = EApp(applied_to_y, some_int, s)
      let outer : Expr = ELam("y", inner, s)
      let out_arg = beta_int_expr(rng, [], depth)
      EApp(outer, out_arg, s)
    }
  }
}

///|
/// 本地生成器：闭合、良类型（顶层 Int）且含字面 lambda 应用 redex 的 `Expr`。
fn beta_redex_gen() -> @infra_pbt.Gen[Expr] {
  @infra_pbt.Gen::new(fn(rng) { beta_redex_at(rng, 3) })
}

///|
/// 判定 `e` 中是否含字面 lambda 应用 redex `EApp(ELam(...), _)`（用于健全性
/// 测试，确保 Property 13 非空真）。
fn beta_contains_redex(e : Expr) -> Bool {
  match e {
    EInt(_, _) | EBool(_, _) | EVar(_, _) => false
    EArith(_, l, r, _) | ECmp(_, l, r, _) | ELogic(_, l, r, _) =>
      beta_contains_redex(l) || beta_contains_redex(r)
    EIf(c, a, b, _) =>
      beta_contains_redex(c) || beta_contains_redex(a) || beta_contains_redex(b)
    ELam(_, body, _) => beta_contains_redex(body)
    EApp(f, a, _) => {
      let here = match f {
        ELam(_, _, _) => true
        _ => false
      }
      here || beta_contains_redex(f) || beta_contains_redex(a)
    }
    ELet(_, e1, e2, _) | ELetRec(_, e1, e2, _) =>
      beta_contains_redex(e1) || beta_contains_redex(e2)
    ETuple(items, _) => {
      for it in items {
        if beta_contains_redex(it) {
          return true
        }
      }
      false
    }
  }
}

// ---------------------------------------------------------------------------
// 健全性：生成器确实产出含 lambda 应用的良类型闭合 Expr（属性非空真前提）
// ---------------------------------------------------------------------------

///|
/// 以固定种子采样 64 次，断言每个产物：(1) 含字面 lambda 应用 redex；
/// (2) `infer` 成功（即良类型闭合）。否则 Property 13 将沦为空真。
test "beta_redex_gen produces well-typed closed exprs containing lambda redexes" {
  let rng = @infra_pbt.rng_new(0x5eed_be7a_1234_5678)
  let g = beta_redex_gen()
  for _ in 0..<64 {
    let e = g.generate(rng)
    assert_true(beta_contains_redex(e))
    let typed = match infer(e) {
      Ok(_) => true
      Err(_) => false
    }
    assert_true(typed)
  }
}

// ---------------------------------------------------------------------------
// Property 13：捕获避免替换正确
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 13: 捕获避免替换正确**
///
/// 对任意由 `beta_redex_gen` 产生的、含字面 lambda 应用的良类型闭合 `Expr`
/// `e`：beta 化简路径 `eval_ml(infer(beta_reduce(e)))` 与原始路径
/// `eval_ml(infer(e))` 所得 `Val` 相等。复用 @infra_pbt 的 `holds_for_all`，
/// 迭代 100 次；任一路 `infer` 失败（理论上不应发生，因生成器与 beta 化简均
/// 保证良类型）即视为属性破坏。
///
/// **Validates: Requirements 7.6**
test "Feature: mini-compiler, Property 13: 捕获避免替换正确" {
  let ok = @infra_pbt.holds_for_all(
    beta_redex_gen(),
    fn(e) {
      // 原始路径：infer 后解释求值。
      let before = match infer(e) {
        Ok((te, _)) => eval_ml(te)
        Err(_) => return false
      }
      // beta 化简路径：beta_reduce 后 infer 再解释求值。
      let reduced = beta_reduce(e)
      let after = match infer(reduced) {
        Ok((te2, _)) => eval_ml(te2)
        Err(_) => return false
      }
      before == after
    },
    iters=100,
  )
  assert_true(ok)
}
