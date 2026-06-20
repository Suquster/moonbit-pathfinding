// ml_gen_test.mbt —— MiniML 属性测试生成器集（task 1.2，覆盖 R12.6）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），基于共享 PBT 包 @infra_pbt 的
// `Gen` / `Rng` 实现 design.md「测试策略」所需的六类生成器，供后续各条属性
// 测试（Property 1–16）复用：
//
//   1. MiniLet `Ast` 生成器          —— minilet_ast_gen
//   2. MiniML `Expr` 生成器          —— ml_expr_gen
//   3. 良类型 `Expr` 生成器          —— ml_well_typed_expr_gen（按目标类型自顶向下构造）
//   4. `Ty` 生成器                   —— ml_ty_gen
//   5. 可合一类型对生成器            —— ml_unifiable_pair_gen
//   6. （规范化）`Subst` 生成器      —— ml_subst_gen
//
// 命名约定：全部生成器与内部助手以 `ml_` / `minilet_` 前缀命名，避免与既有
// 测试文件（prop_roundtrip_test.mbt 的 `gen_ident` / `gen_binop` / `gen_ast`…、
// prop_eval_test.mbt 的 `gen_closed_*` / `scope_with`…）中的符号冲突。
//
// 设计要点：
//   * 全部生成器以 `Gen::new(fn(rng) { ... })` 构造，递归子结构经 fuel（剩余
//     深度）逐层递减以约束树规模，避免生成器产生无界树。
//   * 良类型生成器按**目标类型**自顶向下递归（target ∈ {TyInt, TyBool}），并以
//     in-scope 变量环境保证产物**闭合无自由变量**（可后续通过 infer + 作用域
//     检查），保守起见不生成 lambda——但产物确为良类型且闭合。
//   * 可合一类型对生成器以单调递增的「新鲜变量计数器」保证整对中每个类型变量
//     至多出现一次，从而 unify 不会出现冲突绑定、occurs-check 必通过。
//   * 规范化 Subst 生成器把一组互异类型变量 id 映射到**基类型（无变量）**，
//     使替换幂等（值域不含定义域变量，再次施加不改变结果）。

// ===========================================================================
// 通用采样基元（前缀 ml_ 以避免同包符号冲突）
// ===========================================================================

///|
/// 采样一个非哨兵 span（1 起始行列），用于挂载到生成的 `Expr` 节点。
fn ml_gen_span(rng : @infra_pbt.Rng) -> Span {
  Span::{ line: rng.next_range(1, 64), col: rng.next_range(1, 96) }
}

///|
/// 供变量 / 绑定名采样的合法标识符池（均非 MiniML 关键字）。
let ml_ident_pool : Array[String] = [
  "x", "y", "z", "f", "g", "h", "a", "b", "n", "m",
]

///|
/// 从标识符池随机取一个合法标识符。
fn ml_gen_ident(rng : @infra_pbt.Rng) -> String {
  ml_ident_pool[rng.next_below(ml_ident_pool.length())]
}

///|
/// 随机二元算术运算符（复用既有冻结 `BinOp`）。
fn ml_pick_binop(rng : @infra_pbt.Rng) -> BinOp {
  match rng.next_below(4) {
    0 => Add
    1 => Sub
    2 => Mul
    _ => Div
  }
}

///|
/// 随机比较运算符。
fn ml_pick_cmpop(rng : @infra_pbt.Rng) -> CmpOp {
  match rng.next_below(6) {
    0 => Lt
    1 => Le
    2 => Gt
    3 => Ge
    4 => Eq_
    _ => Ne
  }
}

///|
/// 随机逻辑运算符。
fn ml_pick_logicop(rng : @infra_pbt.Rng) -> LogicOp {
  if rng.next_bool() {
    And
  } else {
    Or
  }
}

///|
/// 在作用域末尾追加 `name` 得到的新数组（不可变更新，便于子树独立采样）。
fn ml_scope_with(scope : Array[String], name : String) -> Array[String] {
  let out : Array[String] = []
  for n in scope {
    out.push(n)
  }
  out.push(name)
  out
}

// ===========================================================================
// 生成器 1：MiniLet `Ast`（minilet_ast_gen）
// ===========================================================================
//
// 产出**闭合**（所有变量都被外层 `let` 绑定）且「打印再解析」往返安全的随机
// MiniLet 表达式：`Bin` 的操作数限定为非顶层 `let`（叶子或嵌套 `Bin`），使
// print_ast 的完全括号化输出可被无歧义解析回同一结构。

///|
/// 采样一个**闭合**叶子节点：作用域非空时可取作用域内变量，否则取非负整数。
fn minilet_leaf(rng : @infra_pbt.Rng, scope : Array[String]) -> Ast {
  if scope.length() > 0 && rng.next_bool() {
    Var(scope[rng.next_below(scope.length())])
  } else {
    Int(rng.next_range(0, 9999))
  }
}

///|
/// 在给定剩余深度与可见作用域下采样闭合 MiniLet `Ast`。
///
/// `allow_let` 为假时不产生顶层 `let`（用于 `Bin` 操作数位置，保证往返）。
fn minilet_ast_at(
  rng : @infra_pbt.Rng,
  scope : Array[String],
  depth : Int,
  allow_let : Bool,
) -> Ast {
  if depth <= 0 {
    minilet_leaf(rng, scope)
  } else if allow_let {
    match rng.next_below(4) {
      0 => minilet_leaf(rng, scope)
      1 | 2 =>
        Bin(
          ml_pick_binop(rng),
          minilet_ast_at(rng, scope, depth - 1, false),
          minilet_ast_at(rng, scope, depth - 1, false),
        )
      _ => {
        let name = ml_gen_ident(rng)
        let bound = minilet_ast_at(rng, scope, depth - 1, true)
        let body = minilet_ast_at(
          rng,
          ml_scope_with(scope, name),
          depth - 1,
          true,
        )
        Let(name, bound, body)
      }
    }
  } else {
    match rng.next_below(2) {
      0 => minilet_leaf(rng, scope)
      _ =>
        Bin(
          ml_pick_binop(rng),
          minilet_ast_at(rng, scope, depth - 1, false),
          minilet_ast_at(rng, scope, depth - 1, false),
        )
    }
  }
}

///|
/// MiniLet `Ast` 生成器：深度受限、闭合、往返安全的随机 MiniLet 表达式。
pub fn minilet_ast_gen() -> @infra_pbt.Gen[Ast] {
  @infra_pbt.Gen::new(fn(rng) { minilet_ast_at(rng, [], 4, true) })
}

// ===========================================================================
// 生成器 2：MiniML `Expr`（ml_expr_gen）
// ===========================================================================
//
// 产出语法上合法、深度受限的随机 `Expr`（可能开放 / 不良类型），覆盖全部
// 非元组构造子，供解析 / 打印往返、作用域检查等语法层属性测试使用。

///|
/// 在给定剩余深度下采样任意 `Expr`。
fn ml_expr_at(rng : @infra_pbt.Rng, depth : Int) -> Expr {
  let sp = ml_gen_span(rng)
  if depth <= 0 {
    match rng.next_below(3) {
      0 => EInt(rng.next_range(0, 9999), sp)
      1 => EBool(rng.next_bool(), sp)
      _ => EVar(ml_gen_ident(rng), sp)
    }
  } else {
    let sub = fn() { ml_expr_at(rng, depth - 1) }
    match rng.next_below(11) {
      0 => EInt(rng.next_range(0, 9999), sp)
      1 => EBool(rng.next_bool(), sp)
      2 => EVar(ml_gen_ident(rng), sp)
      3 => EArith(ml_pick_binop(rng), sub(), sub(), sp)
      4 => ECmp(ml_pick_cmpop(rng), sub(), sub(), sp)
      5 => ELogic(ml_pick_logicop(rng), sub(), sub(), sp)
      6 => EIf(sub(), sub(), sub(), sp)
      7 => ELam(ml_gen_ident(rng), sub(), sp)
      8 => EApp(sub(), sub(), sp)
      9 => ELet(ml_gen_ident(rng), sub(), sub(), sp)
      _ => ELetRec(ml_gen_ident(rng), sub(), sub(), sp)
    }
  }
}

///|
/// MiniML `Expr` 生成器：深度受限的随机语法树（不保证良类型 / 闭合）。
pub fn ml_expr_gen() -> @infra_pbt.Gen[Expr] {
  @infra_pbt.Gen::new(fn(rng) { ml_expr_at(rng, 4) })
}

// ===========================================================================
// 生成器 3：良类型 `Expr`（ml_well_typed_expr_gen）—— 按目标类型自顶向下构造
// ===========================================================================
//
// 以目标类型（TyInt / TyBool）驱动递归构造，并以 (名字, 类型) 环境保证变量
// 引用必落在某个外层 `let` 绑定上 —— 故产物既闭合又良类型（保守起见不生成
// lambda / 应用，但完全满足「可被 infer 成功且通过作用域检查」的要求）。

///|
/// 收集环境中类型恰为 `ty` 的变量名。
fn ml_vars_of_type(env : Array[(String, Ty)], ty : Ty) -> Array[String] {
  let out : Array[String] = []
  for pair in env {
    let (name, vty) = pair
    if vty == ty {
      out.push(name)
    }
  }
  out
}

///|
/// 随机基类型（TyInt / TyBool），用于 `let` 绑定体的目标类型。
fn ml_base_ty(rng : @infra_pbt.Rng) -> Ty {
  if rng.next_bool() {
    TyInt
  } else {
    TyBool
  }
}

///|
/// 采样一个目标类型为 `target` 的**良类型闭合**叶子表达式。
fn ml_wt_leaf(
  rng : @infra_pbt.Rng,
  target : Ty,
  env : Array[(String, Ty)],
) -> Expr {
  let sp = ml_gen_span(rng)
  let candidates = ml_vars_of_type(env, target)
  if candidates.length() > 0 && rng.next_bool() {
    EVar(candidates[rng.next_below(candidates.length())], sp)
  } else {
    match target {
      TyBool => EBool(rng.next_bool(), sp)
      _ => EInt(rng.next_range(0, 9999), sp)
    }
  }
}

///|
/// 按目标类型自顶向下采样良类型闭合 `Expr`。
fn ml_wt_at(
  rng : @infra_pbt.Rng,
  target : Ty,
  env : Array[(String, Ty)],
  depth : Int,
) -> Expr {
  let sp = ml_gen_span(rng)
  if depth <= 0 {
    ml_wt_leaf(rng, target, env)
  } else {
    match target {
      TyBool =>
        match rng.next_below(5) {
          0 => ml_wt_leaf(rng, target, env)
          1 =>
            ECmp(
              ml_pick_cmpop(rng),
              ml_wt_at(rng, TyInt, env, depth - 1),
              ml_wt_at(rng, TyInt, env, depth - 1),
              sp,
            )
          2 =>
            ELogic(
              ml_pick_logicop(rng),
              ml_wt_at(rng, TyBool, env, depth - 1),
              ml_wt_at(rng, TyBool, env, depth - 1),
              sp,
            )
          3 =>
            EIf(
              ml_wt_at(rng, TyBool, env, depth - 1),
              ml_wt_at(rng, TyBool, env, depth - 1),
              ml_wt_at(rng, TyBool, env, depth - 1),
              sp,
            )
          _ => {
            let name = ml_gen_ident(rng)
            let bt = ml_base_ty(rng)
            let bound = ml_wt_at(rng, bt, env, depth - 1)
            let body = ml_wt_at(
              rng,
              TyBool,
              ml_scope_with_typed(env, name, bt),
              depth - 1,
            )
            ELet(name, bound, body, sp)
          }
        }
      // 缺省按整数类型处理（target 顶层仅取 TyInt / TyBool）。
      _ =>
        match rng.next_below(4) {
          0 => ml_wt_leaf(rng, target, env)
          1 =>
            EArith(
              ml_pick_binop(rng),
              ml_wt_at(rng, TyInt, env, depth - 1),
              ml_wt_at(rng, TyInt, env, depth - 1),
              sp,
            )
          2 =>
            EIf(
              ml_wt_at(rng, TyBool, env, depth - 1),
              ml_wt_at(rng, TyInt, env, depth - 1),
              ml_wt_at(rng, TyInt, env, depth - 1),
              sp,
            )
          _ => {
            let name = ml_gen_ident(rng)
            let bt = ml_base_ty(rng)
            let bound = ml_wt_at(rng, bt, env, depth - 1)
            let body = ml_wt_at(
              rng,
              TyInt,
              ml_scope_with_typed(env, name, bt),
              depth - 1,
            )
            ELet(name, bound, body, sp)
          }
        }
    }
  }
}

///|
/// 在带类型环境末尾追加 (name, ty) 得到的新环境。
fn ml_scope_with_typed(
  env : Array[(String, Ty)],
  name : String,
  ty : Ty,
) -> Array[(String, Ty)] {
  let out : Array[(String, Ty)] = []
  for pair in env {
    out.push(pair)
  }
  out.push((name, ty))
  out
}

///|
/// 良类型 `Expr` 生成器：闭合、可被类型推断成功的随机 MiniML 表达式。
pub fn ml_well_typed_expr_gen() -> @infra_pbt.Gen[Expr] {
  @infra_pbt.Gen::new(fn(rng) {
    let target : Ty = if rng.next_bool() { TyInt } else { TyBool }
    ml_wt_at(rng, target, [], 4)
  })
}

// ===========================================================================
// 生成器 4：`Ty`（ml_ty_gen）
// ===========================================================================

///|
/// 在给定剩余深度下采样任意类型项。
fn ml_ty_at(rng : @infra_pbt.Rng, depth : Int) -> Ty {
  if depth <= 0 {
    match rng.next_below(3) {
      0 => TyInt
      1 => TyBool
      _ => TyVar(rng.next_below(5))
    }
  } else {
    match rng.next_below(5) {
      0 => TyInt
      1 => TyBool
      2 => TyVar(rng.next_below(5))
      3 => TyFun(ml_ty_at(rng, depth - 1), ml_ty_at(rng, depth - 1))
      _ => {
        let n = 2 + rng.next_below(2)
        let arr : Array[Ty] = []
        for _ in 0..<n {
          arr.push(ml_ty_at(rng, depth - 1))
        }
        TyTuple(arr)
      }
    }
  }
}

///|
/// `Ty` 生成器：深度受限的随机类型项（含变量 / 函数 / 元组）。
pub fn ml_ty_gen() -> @infra_pbt.Gen[Ty] {
  @infra_pbt.Gen::new(fn(rng) { ml_ty_at(rng, 3) })
}

// ===========================================================================
// 生成器 5：可合一类型对（ml_unifiable_pair_gen）
// ===========================================================================
//
// 构造原则：以单调递增的新鲜变量计数器 `fresh`（单元素数组作可变 cell）保证
// 整对中每个类型变量 id 至多出现一次。基类型部分为「无变量」的 ground 类型，
// 故每个变量都单独地与一个具体类型项配对，unify 必成功且 occurs-check 必通过。

///|
/// 采样一个无类型变量的 ground 类型（TyInt / TyBool / 其上的函数 / 元组）。
fn ml_ground_ty(rng : @infra_pbt.Rng, depth : Int) -> Ty {
  if depth <= 0 {
    if rng.next_bool() {
      TyInt
    } else {
      TyBool
    }
  } else {
    match rng.next_below(4) {
      0 => TyInt
      1 => TyBool
      2 => TyFun(ml_ground_ty(rng, depth - 1), ml_ground_ty(rng, depth - 1))
      _ => {
        let n = 2 + rng.next_below(2)
        let arr : Array[Ty] = []
        for _ in 0..<n {
          arr.push(ml_ground_ty(rng, depth - 1))
        }
        TyTuple(arr)
      }
    }
  }
}

///|
/// 取下一个新鲜类型变量 id（自增可变 cell）。
fn ml_next_fresh(fresh : Array[Int]) -> Int {
  let v = fresh[0]
  fresh[0] = v + 1
  v
}

///|
/// 递归构造一对可合一类型项 `(left, right)`。
fn ml_unif_pair_at(
  rng : @infra_pbt.Rng,
  fresh : Array[Int],
  depth : Int,
) -> (Ty, Ty) {
  if depth <= 0 {
    match rng.next_below(4) {
      0 => {
        let g = ml_ground_ty(rng, 1)
        (g, g)
      }
      1 => {
        let g = ml_ground_ty(rng, 1)
        (TyVar(ml_next_fresh(fresh)), g)
      }
      2 => {
        let g = ml_ground_ty(rng, 1)
        (g, TyVar(ml_next_fresh(fresh)))
      }
      _ => {
        let v = ml_next_fresh(fresh)
        let w = ml_next_fresh(fresh)
        (TyVar(v), TyVar(w))
      }
    }
  } else {
    match rng.next_below(3) {
      0 => ml_unif_pair_at(rng, fresh, 0)
      1 => {
        let (l1, r1) = ml_unif_pair_at(rng, fresh, depth - 1)
        let (l2, r2) = ml_unif_pair_at(rng, fresh, depth - 1)
        (TyFun(l1, l2), TyFun(r1, r2))
      }
      _ => {
        let n = 2 + rng.next_below(2)
        let ls : Array[Ty] = []
        let rs : Array[Ty] = []
        for _ in 0..<n {
          let (l, r) = ml_unif_pair_at(rng, fresh, depth - 1)
          ls.push(l)
          rs.push(r)
        }
        (TyTuple(ls), TyTuple(rs))
      }
    }
  }
}

///|
/// 可合一类型对生成器：产出一定可被 `unify` 成功合一的 `(Ty, Ty)`。
pub fn ml_unifiable_pair_gen() -> @infra_pbt.Gen[(Ty, Ty)] {
  @infra_pbt.Gen::new(fn(rng) {
    let fresh = [1000]
    ml_unif_pair_at(rng, fresh, 3)
  })
}

// ===========================================================================
// 生成器 6：（规范化）`Subst`（ml_subst_gen）
// ===========================================================================
//
// 把一组互异类型变量 id（0..n-1）映射到无变量的 ground 类型。值域不含定义域
// 变量，故替换幂等：apply_subst(s, apply_subst(s, t)) == apply_subst(s, t)。

///|
/// 构造一个规范化（幂等）替换。
fn ml_subst_build(rng : @infra_pbt.Rng) -> Subst {
  let n = rng.next_below(5)
  let mut m : @sorted_map.SortedMap[Int, Ty] = @sorted_map.SortedMap::new()
  for i in 0..<n {
    m = m.add(i, ml_ground_ty(rng, 2))
  }
  Subst::{ map: m }
}

///|
/// （规范化）`Subst` 生成器：定义域互异、值域为基类型的幂等替换。
pub fn ml_subst_gen() -> @infra_pbt.Gen[Subst] {
  @infra_pbt.Gen::new(fn(rng) { ml_subst_build(rng) })
}

// ===========================================================================
// 健全性测试（sanity）—— 以固定种子各采样若干次，确认六类生成器均可产出值
// ===========================================================================

///|
/// 以固定种子采样六类生成器各 8 次，断言均能产出值（借 derive(Eq) 强制求值），
/// 使本文件成为可被 `moon test` 实际运行的有效测试文件。
test "ml generators produce values across all six kinds" {
  let rng = @infra_pbt.rng_new(0x1234_5678_9abc_def0)
  let minilet = minilet_ast_gen()
  let expr = ml_expr_gen()
  let wt = ml_well_typed_expr_gen()
  let ty = ml_ty_gen()
  let pair = ml_unifiable_pair_gen()
  let subst = ml_subst_gen()
  for _ in 0..<8 {
    let a = minilet.generate(rng)
    assert_true(a == a)
    let e = expr.generate(rng)
    assert_true(e == e)
    let w = wt.generate(rng)
    assert_true(w == w)
    let t = ty.generate(rng)
    assert_true(t == t)
    let (l, r) = pair.generate(rng)
    assert_true(l == l && r == r)
    let s = subst.generate(rng)
    assert_true(s == s)
  }
}

///|
/// 良类型生成器的产物应为闭合表达式（无自由变量）：以一个简单的自由变量检查
/// 见证——遍历 AST 收集自由变量集合应为空。这是「可后续通过 infer + 作用域
/// 检查」的必要前提。
test "well-typed generator produces closed expressions" {
  let rng = @infra_pbt.rng_new(0x0bad_c0de_dead_beef)
  let wt = ml_well_typed_expr_gen()
  for _ in 0..<32 {
    let e = wt.generate(rng)
    assert_true(ml_free_vars(e, []).length() == 0)
  }
}

///|
/// 收集 `Expr` 中相对于已绑定集合 `bound` 的自由变量（仅供上面的健全性测试用）。
fn ml_free_vars(e : Expr, bound : Array[String]) -> Array[String] {
  let acc : Array[String] = []
  ml_collect_free(e, bound, acc)
  acc
}

///|
/// 递归收集自由变量到 `acc`。
fn ml_collect_free(
  e : Expr,
  bound : Array[String],
  acc : Array[String],
) -> Unit {
  match e {
    EInt(_, _) | EBool(_, _) => ()
    EVar(name, _) => if !ml_mem(bound, name) { acc.push(name) }
    EArith(_, l, r, _)
    | ECmp(_, l, r, _)
    | ELogic(_, l, r, _)
    | EApp(l, r, _) => {
      ml_collect_free(l, bound, acc)
      ml_collect_free(r, bound, acc)
    }
    EIf(c, a, b, _) => {
      ml_collect_free(c, bound, acc)
      ml_collect_free(a, bound, acc)
      ml_collect_free(b, bound, acc)
    }
    ELam(p, body, _) => ml_collect_free(body, ml_scope_with(bound, p), acc)
    ELet(name, bound_e, body, _) => {
      ml_collect_free(bound_e, bound, acc)
      ml_collect_free(body, ml_scope_with(bound, name), acc)
    }
    ELetRec(name, bound_e, body, _) => {
      let inner = ml_scope_with(bound, name)
      ml_collect_free(bound_e, inner, acc)
      ml_collect_free(body, inner, acc)
    }
    ETuple(items, _) =>
      for it in items {
        ml_collect_free(it, bound, acc)
      }
  }
}

///|
/// 判定 `name` 是否在 `bound` 中。
fn ml_mem(bound : Array[String], name : String) -> Bool {
  for n in bound {
    if n == name {
      return true
    }
  }
  false
}
