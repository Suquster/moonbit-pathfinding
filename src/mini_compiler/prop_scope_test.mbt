// prop_scope_test.mbt —— MiniML 作用域检查属性测试（task 7.5，Property 14）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），验证 `scope_check_ml`（ml_eval.mbt）
// 恰好接受全部变量引用都能解析到某个绑定的「闭合」程序、拒绝含自由变量的程序。
//
// 设计要点：
//   * 复用 task 1.2（ml_gen_test.mbt）的通用 `Expr` 生成器 `ml_expr_gen()`——其
//     产物**可能开放（含自由变量）也可能闭合**，故同时驱动「接受」与「拒绝」
//     两条路径，恰好覆盖本属性的双向输入空间。
//   * 本文件实现一个**独立预言**（oracle）`has_free_vars`，从零计算 `Expr` 是否
//     含自由变量。其作用域规则严格镜像 `scope_check_ml`（见 ml_eval.mbt 的
//     `scope_check_go`）：`ELam` 形参在体内可见；`ELet` 绑定名仅在 body 可见
//     （不在 e1）；`ELetRec` 递归名在 e1 与 e2 **均**可见；`EVar` 不在已绑定
//     集合内即为自由变量。
//   * 属性谓词断言 `scope_check_ml(e)` 返回 `Ok` 当且仅当 `e` 闭合：
//       - `Ok(_)`  ⇒ e 必须闭合（不含自由变量）；
//       - `Err(d)` ⇒ e 必须含自由变量，且诊断 `kind == TypeError`（R8.4）。
//   * 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代 100 次
//     （满足「每条属性测试 ≥100 迭代」基线）。

// **Feature: mini-compiler, Property 14: 作用域检查正确**
// **Validates: Requirements 8.6**

///|
/// 独立预言：`e` 是否含相对于空初始作用域的自由变量。
///
/// 作用域规则镜像 `scope_check_ml`（ml_eval.mbt）：`ELam` 形参在体内引入；
/// `ELet` 绑定名仅在 body 引入（不在 e1）；`ELetRec` 递归名在 e1 与 e2 均引入。
fn has_free_vars(e : Expr) -> Bool {
  scope_oracle_go(e, [])
}

///|
/// 判定 `name` 是否在已绑定名集合 `bound` 中。
fn scope_oracle_mem(bound : Array[String], name : String) -> Bool {
  for n in bound {
    if n == name {
      return true
    }
  }
  false
}

///|
/// 在已绑定集合末尾追加 `name` 得到的新集合（不可变更新，便于子树独立递归）。
fn scope_oracle_with(bound : Array[String], name : String) -> Array[String] {
  let out : Array[String] = []
  for n in bound {
    out.push(n)
  }
  out.push(name)
  out
}

///|
/// 递归判定 `e` 在已绑定集合 `bound` 下是否含自由变量。
fn scope_oracle_go(e : Expr, bound : Array[String]) -> Bool {
  match e {
    EInt(_, _) | EBool(_, _) => false
    EVar(name, _) => !scope_oracle_mem(bound, name)
    EArith(_, l, r, _)
    | ECmp(_, l, r, _)
    | ELogic(_, l, r, _)
    | EApp(l, r, _) => scope_oracle_go(l, bound) || scope_oracle_go(r, bound)
    EIf(c, a, b, _) =>
      scope_oracle_go(c, bound) ||
      scope_oracle_go(a, bound) ||
      scope_oracle_go(b, bound)
    // 形参在函数体内可见。
    ELam(p, body, _) => scope_oracle_go(body, scope_oracle_with(bound, p))
    // 非递归 let：e1 在外层作用域；body 在引入 name 后。
    ELet(name, e1, e2, _) =>
      scope_oracle_go(e1, bound) ||
      scope_oracle_go(e2, scope_oracle_with(bound, name))
    // 递归 let：name 在 e1 与 e2 均可见。
    ELetRec(name, e1, e2, _) => {
      let inner = scope_oracle_with(bound, name)
      scope_oracle_go(e1, inner) || scope_oracle_go(e2, inner)
    }
    ETuple(items, _) => {
      for it in items {
        if scope_oracle_go(it, bound) {
          return true
        }
      }
      false
    }
  }
}

///|
/// **Feature: mini-compiler, Property 14: 作用域检查正确**
///
/// 对任意 `Expr` `e`，`scope_check_ml(e)` 返回 `Ok` 当且仅当 `e` 闭合（不含
/// 自由变量）：闭合程序被接受、含自由变量的程序被拒绝（诊断 `kind == TypeError`）。
/// 独立预言 `has_free_vars` 镜像 `scope_check_ml` 的作用域规则。生成器
/// `ml_expr_gen` 同时产出开放与闭合表达式，故接受与拒绝两条路径均被覆盖。
/// 复用 @infra_pbt 的 `holds_for_all`，迭代 100 次。
///
/// **Validates: Requirements 8.6**
test "Feature: mini-compiler, Property 14: 作用域检查正确" {
  let ok = @infra_pbt.holds_for_all(
    ml_expr_gen(),
    fn(e) {
      let is_closed = !has_free_vars(e)
      match scope_check_ml(e) {
        // 接受 ⟺ 闭合。
        Ok(_) => is_closed
        // 拒绝 ⟺ 含自由变量，且为 TypeError 诊断。
        Err(d) => !is_closed && d.kind == TypeError
      }
    },
    iters=100,
  )
  assert_true(ok)
}
