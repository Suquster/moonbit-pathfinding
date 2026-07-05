// optimize.mbt —— MiniML AST 优化管线（design.md §11，覆盖 R7.1 ~ R7.6）。
//
// 本文件在 `Expr`（未标注类型的语法树）上实现三类**语义保持**变换，作为
// infer 之后、eval/编译之前的可选优化阶段（design §12 流水线顺序
// `lex_ml → parse_ml → infer → (可选)optimize → eval_ml`；优化在 `Expr` 上
// 定义，流水线对解析所得 `Expr` 施加后再 infer——见 Property 11/12）：
//
//   * `const_fold`：自底向上常量折叠。把**仅由常量构成**的算术 / 比较 / 逻辑
//     子表达式预先求值为字面量节点；并对 `if` 的常量条件做分支选择（R7.1）。
//     折叠规则与 ml_eval.mbt 的 `ml_apply_arith` / `ml_apply_cmp` **逐字一致**
//     ——尤其**除零定义为 0**、`Int` 为 32 位环绕算术——从而保持语义且三后端
//     一致。常量折叠在任意上下文（包括 lambda 体内）都成立，故对子节点无条件
//     递归。
//
//   * `dead_let_elim`：死 `let` 消除。若绑定名在（已优化的）body 中**自由出现
//     零次**，则以 body 取代整个 `let`，丢弃绑定体（R7.2）。
//     **纯性 / 全函数论证**：MiniML 是**纯**语言——表达式无赋值、无 I/O、无
//     异常等任何可观察副作用；且 `eval_ml` 是**全函数**（除零=0、变量必有绑定、
//     无未定义行为，见 ml_eval.mbt）。因此求值一个绑定体**不可能**产生除「得到
//     一个值」以外的任何效果，丢弃一个从不被引用的绑定体**不改变**程序的可观察
//     结果。故死 `let` 消除在 MiniML 中无条件语义保持（无需副作用分析）。
//     `let rec f = e1 in e2`：递归名 `f` 仅经由 `e2` 中对 `f` 的引用可达；`e1`
//     内部对 `f` 的自引用在 `f` 不被 `e2` 使用时不可观察，故 `f` 在 `e2'` 中
//     自由出现零次时，整个 `letrec` 可由 `e2'` 取代。
//
//   * `beta_reduce`：beta 化简（可选，**不**包含在 `optimize` 内，R7.3）。对
//     字面 lambda 的应用 `(λx. body) arg` 做**捕获避免替换** `body[x ↦ arg]`。
//     替换 `subst_expr` 在下降至绑定子（`ELam` / `ELet` / `ELetRec` 的绑定名）
//     时遵守词法作用域：被同名绑定遮蔽处停止替换；当绑定名 `y` 自由出现于
//     `arg` 且 `y != x` 时，对该绑定子做 **alpha 重命名**到一个全新名字，避免
//     `arg` 的自由变量被意外捕获（design 术语「捕获避免替换」）。新鲜名经
//     `fresh_name` 生成并校验不与 body/arg 的自由变量冲突。
//
//   * `optimize`：组合管线 `const_fold ∘ dead_let_elim`（先死 let 消除再常量
//     折叠），默认**不含** beta（R7.4 / R7.5）。保证输出仍良类型且语义等价。
//
// 全部函数为**全函数**并尽量保留各节点的原始 span。本文件**不修改**任何既有
// 文件（含 ml_types.mbt），全部能力旁路新增（R12.4）。

// ---------------------------------------------------------------------------
// 常量折叠（R7.1）
// ---------------------------------------------------------------------------

///|
/// 常量折叠：自底向上把仅由常量构成的算术 / 比较 / 逻辑子表达式预求值为字面量
/// 节点，并对常量 `if` 条件做分支选择（R7.1）。
///
/// 折叠语义与 ml_eval.mbt 完全一致（除零=0、32 位环绕算术），故保持语义；折叠
/// 在任意上下文成立，因此对所有子节点无条件递归（含 lambda 体内）。保留节点原
/// 始 span。
pub fn const_fold(e : Expr) -> Expr {
  match e {
    EInt(_, _) | EBool(_, _) | EVar(_, _) => e
    EArith(op, l, r, sp) => {
      let lf = const_fold(l)
      let rf = const_fold(r)
      match (lf, rf) {
        (EInt(a, _), EInt(b, _)) => EInt(fold_arith(op, a, b), sp)
        _ => EArith(op, lf, rf, sp)
      }
    }
    ECmp(op, l, r, sp) => {
      let lf = const_fold(l)
      let rf = const_fold(r)
      match (lf, rf) {
        (EInt(a, _), EInt(b, _)) => EBool(fold_cmp(op, a, b), sp)
        _ => ECmp(op, lf, rf, sp)
      }
    }
    ELogic(op, l, r, sp) => {
      let lf = const_fold(l)
      let rf = const_fold(r)
      match (lf, rf) {
        (EBool(a, _), EBool(b, _)) =>
          EBool(
            match op {
              And => a && b
              Or => a || b
            },
            sp,
          )
        _ => ELogic(op, lf, rf, sp)
      }
    }
    EIf(c, a, b, sp) => {
      let cf = const_fold(c)
      let af = const_fold(a)
      let bf = const_fold(b)
      match cf {
        EBool(true, _) => af
        EBool(false, _) => bf
        _ => EIf(cf, af, bf, sp)
      }
    }
    ELam(x, body, sp) => ELam(x, const_fold(body), sp)
    EApp(f, a, sp) => EApp(const_fold(f), const_fold(a), sp)
    ELet(x, e1, e2, sp) => ELet(x, const_fold(e1), const_fold(e2), sp)
    ELetRec(f, e1, e2, sp) => ELetRec(f, const_fold(e1), const_fold(e2), sp)
    ETuple(items, sp) => ETuple(items.map(const_fold), sp)
  }
}

///|
/// 施加常量算术折叠；除零定义为 0（与 ml_eval.mbt `ml_apply_arith` 一致，R7.1）。
fn fold_arith(op : BinOp, a : Int, b : Int) -> Int {
  match op {
    Add => a + b
    Sub => a - b
    Mul => a * b
    Div =>
      if b == 0 {
        0
      } else if b == -1 {
        // INT_MIN / -1 不可表示（trap）；按环绕语义定义为 0 - a（与 ml_eval 一致）。
        0 - a
      } else {
        a / b
      }
  }
}

///|
/// 施加常量比较折叠（与 ml_eval.mbt `ml_apply_cmp` 一致，R7.1）。
fn fold_cmp(op : CmpOp, a : Int, b : Int) -> Bool {
  match op {
    Lt => a < b
    Le => a <= b
    Gt => a > b
    Ge => a >= b
    Eq_ => a == b
    Ne => a != b
  }
}

// ---------------------------------------------------------------------------
// 自由变量出现（尊重绑定子）
// ---------------------------------------------------------------------------

///|
/// `name` 是否在 `e` 中**自由出现**（尊重 `ELam` / `ELet` / `ELetRec` 引入的
/// 绑定子的作用域，用于死 `let` 消除与捕获避免替换）。
///
/// 作用域规则（与 ml_eval.mbt `scope_check_go` 对齐）：`ELam` 形参在体内绑定；
/// `ELet` 的名仅在 body 绑定（不在 e1）；`ELetRec` 的名在 e1 与 e2 **均**绑定。
fn occurs_free(name : String, e : Expr) -> Bool {
  match e {
    EInt(_, _) => false
    EBool(_, _) => false
    EVar(x, _) => x == name
    EArith(_, l, r, _) => occurs_free(name, l) || occurs_free(name, r)
    ECmp(_, l, r, _) => occurs_free(name, l) || occurs_free(name, r)
    ELogic(_, l, r, _) => occurs_free(name, l) || occurs_free(name, r)
    EIf(c, a, b, _) =>
      occurs_free(name, c) || occurs_free(name, a) || occurs_free(name, b)
    ELam(x, body, _) => if x == name { false } else { occurs_free(name, body) }
    EApp(f, a, _) => occurs_free(name, f) || occurs_free(name, a)
    ELet(x, e1, e2, _) =>
      occurs_free(name, e1) ||
      (if x == name { false } else { occurs_free(name, e2) })
    ELetRec(f, e1, e2, _) =>
      if f == name {
        false
      } else {
        occurs_free(name, e1) || occurs_free(name, e2)
      }
    ETuple(items, _) => {
      for it in items {
        if occurs_free(name, it) {
          return true
        }
      }
      false
    }
  }
}

// ---------------------------------------------------------------------------
// 死 let 消除（R7.2）
// ---------------------------------------------------------------------------

///|
/// 死 `let` 消除：删除其绑定名在（已优化的）body 中从不自由出现的 `let` /
/// `let rec`，以 body 取代之（R7.2）。
///
/// 依赖 MiniML 的纯性与 `eval_ml` 的全函数性（见文件头论证）：丢弃一个从不被
/// 引用的绑定体不产生任何可观察效果，故无条件语义保持。其余构造子重建已处理的
/// 子节点。保留节点原始 span。
pub fn dead_let_elim(e : Expr) -> Expr {
  match e {
    EInt(_, _) | EBool(_, _) | EVar(_, _) => e
    EArith(op, l, r, sp) => EArith(op, dead_let_elim(l), dead_let_elim(r), sp)
    ECmp(op, l, r, sp) => ECmp(op, dead_let_elim(l), dead_let_elim(r), sp)
    ELogic(op, l, r, sp) => ELogic(op, dead_let_elim(l), dead_let_elim(r), sp)
    EIf(c, a, b, sp) =>
      EIf(dead_let_elim(c), dead_let_elim(a), dead_let_elim(b), sp)
    ELam(x, body, sp) => ELam(x, dead_let_elim(body), sp)
    EApp(f, a, sp) => EApp(dead_let_elim(f), dead_let_elim(a), sp)
    ELet(x, e1, e2, sp) => {
      let e1p = dead_let_elim(e1)
      let e2p = dead_let_elim(e2)
      if occurs_free(x, e2p) {
        ELet(x, e1p, e2p, sp)
      } else {
        e2p
      }
    }
    ELetRec(f, e1, e2, sp) => {
      let e1p = dead_let_elim(e1)
      let e2p = dead_let_elim(e2)
      if occurs_free(f, e2p) {
        ELetRec(f, e1p, e2p, sp)
      } else {
        e2p
      }
    }
    ETuple(items, sp) => ETuple(items.map(dead_let_elim), sp)
  }
}

// ---------------------------------------------------------------------------
// beta 化简与捕获避免替换（R7.3 / R7.6，可选）
// ---------------------------------------------------------------------------

///|
/// 生成一个不与 `avoid` 中任何名字冲突的新鲜名（基于 `base` 追加递增计数器）。
/// 用于 alpha 重命名以实现捕获避免替换。
fn fresh_name(base : String, avoid : (String) -> Bool) -> String {
  let mut i = 0
  let mut candidate = base + "#" + i.to_string()
  while avoid(candidate) {
    i = i + 1
    candidate = base + "#" + i.to_string()
  }
  candidate
}

///|
/// 捕获避免替换：把 `body` 中 `x` 的**自由**出现替换为 `arg`（R7.3 / R7.6）。
///
/// 在下降至绑定子（`ELam` / `ELet` body / `ELetRec`）时：
///   * 若绑定名 `== x`：`x` 在该子树被遮蔽，停止替换（保持词法作用域）。
///   * 否则若绑定名 `y` 自由出现于 `arg`：直接替换会使 `arg` 中的 `y` 被该
///     绑定子捕获，故先把绑定子 alpha 重命名为新鲜名 `y'`（更新其绑定体内 `y`
///     的引用），再继续替换。新鲜名校验不与 `x`、`arg` 自由变量、`body` 自由
///     变量冲突。
fn subst_expr(x : String, arg : Expr, body : Expr) -> Expr {
  match body {
    EInt(_, _) | EBool(_, _) => body
    EVar(y, _) => if y == x { arg } else { body }
    EArith(op, l, r, sp) =>
      EArith(op, subst_expr(x, arg, l), subst_expr(x, arg, r), sp)
    ECmp(op, l, r, sp) =>
      ECmp(op, subst_expr(x, arg, l), subst_expr(x, arg, r), sp)
    ELogic(op, l, r, sp) =>
      ELogic(op, subst_expr(x, arg, l), subst_expr(x, arg, r), sp)
    EIf(c, a, b, sp) =>
      EIf(
        subst_expr(x, arg, c),
        subst_expr(x, arg, a),
        subst_expr(x, arg, b),
        sp,
      )
    EApp(f, a, sp) => EApp(subst_expr(x, arg, f), subst_expr(x, arg, a), sp)
    ELam(y, lbody, sp) =>
      if y == x {
        // x 被形参 y 遮蔽，停止替换。
        body
      } else if occurs_free(y, arg) {
        // 避免捕获：alpha 重命名形参 y -> y'。
        let yp = fresh_name(y, fn(n) {
          n == x || occurs_free(n, arg) || occurs_free(n, lbody)
        })
        let renamed = subst_expr(y, EVar(yp, sp), lbody)
        ELam(yp, subst_expr(x, arg, renamed), sp)
      } else {
        ELam(y, subst_expr(x, arg, lbody), sp)
      }
    ELet(y, e1, e2, sp) => {
      // e1 不在 y 的作用域内：始终替换。
      let e1s = subst_expr(x, arg, e1)
      if y == x {
        // body e2 中 x 被遮蔽。
        ELet(y, e1s, e2, sp)
      } else if occurs_free(y, arg) {
        let yp = fresh_name(y, fn(n) {
          n == x || occurs_free(n, arg) || occurs_free(n, e2)
        })
        let e2r = subst_expr(y, EVar(yp, sp), e2)
        ELet(yp, e1s, subst_expr(x, arg, e2r), sp)
      } else {
        ELet(y, e1s, subst_expr(x, arg, e2), sp)
      }
    }
    ELetRec(f, e1, e2, sp) =>
      if f == x {
        // f 在 e1 与 e2 均遮蔽 x。
        body
      } else if occurs_free(f, arg) {
        // f 在 e1 与 e2 均绑定：一并 alpha 重命名。
        let fp = fresh_name(f, fn(n) {
          n == x ||
          occurs_free(n, arg) ||
          occurs_free(n, e1) ||
          occurs_free(n, e2)
        })
        let e1r = subst_expr(f, EVar(fp, sp), e1)
        let e2r = subst_expr(f, EVar(fp, sp), e2)
        ELetRec(fp, subst_expr(x, arg, e1r), subst_expr(x, arg, e2r), sp)
      } else {
        ELetRec(f, subst_expr(x, arg, e1), subst_expr(x, arg, e2), sp)
      }
    ETuple(items, sp) =>
      ETuple(items.map(fn(it) { subst_expr(x, arg, it) }), sp)
  }
}

///|
/// beta 化简：对字面 lambda 的应用 `(λx. body) arg` 做捕获避免替换
/// `body[x ↦ arg]`，并递归化简嵌套 redex（R7.3 / R7.6）。**不**含于 `optimize`。
pub fn beta_reduce(e : Expr) -> Expr {
  match e {
    EInt(_, _) | EBool(_, _) | EVar(_, _) => e
    EArith(op, l, r, sp) => EArith(op, beta_reduce(l), beta_reduce(r), sp)
    ECmp(op, l, r, sp) => ECmp(op, beta_reduce(l), beta_reduce(r), sp)
    ELogic(op, l, r, sp) => ELogic(op, beta_reduce(l), beta_reduce(r), sp)
    EIf(c, a, b, sp) => EIf(beta_reduce(c), beta_reduce(a), beta_reduce(b), sp)
    ELam(x, body, sp) => ELam(x, beta_reduce(body), sp)
    EApp(f, a, sp) => {
      let fr = beta_reduce(f)
      let ar = beta_reduce(a)
      match fr {
        ELam(x, lbody, _) =>
          // (λx. lbody) ar  -->  lbody[x ↦ ar]，再化简产生的新 redex。
          beta_reduce(subst_expr(x, ar, lbody))
        _ => EApp(fr, ar, sp)
      }
    }
    ELet(x, e1, e2, sp) => ELet(x, beta_reduce(e1), beta_reduce(e2), sp)
    ELetRec(f, e1, e2, sp) => ELetRec(f, beta_reduce(e1), beta_reduce(e2), sp)
    ETuple(items, sp) => ETuple(items.map(beta_reduce), sp)
  }
}

// ---------------------------------------------------------------------------
// 组合优化管线（R7.4 / R7.5）
// ---------------------------------------------------------------------------

///|
/// 组合优化管线：`const_fold ∘ dead_let_elim`（先死 `let` 消除再常量折叠），
/// 默认**不含** beta（R7.4 / R7.5）。保证输出仍良类型且与输入语义等价。
pub fn optimize(e : Expr) -> Expr {
  const_fold(dead_let_elim(e))
}
