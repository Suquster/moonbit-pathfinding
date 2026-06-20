// ml_printer.mbt —— MiniML 抽象语法树 → 源串（`print_expr`）与去 span 规范化
// （`erase_span`）。
//
// 对应任务 2.3（design.md §「4. 打印器（ml_printer.mbt，R2.4 / R2.5）」）：
// 旁路新增的 MiniML 打印器。本文件**不修改**任何既有文件，全部能力旁路新增。
//
// 设计要点（R2.4）：`print_expr` 对二元 / 比较 / 逻辑 / 应用节点采用**完全括号
// 化**策略，使打印产物的重新解析与运算符优先级 / 结合性无关地还原同一树形。
// 进一步地，`if` / `lambda`(`fun`) / `let` / `let rec` 这些本只能出现在 `expr`
// 层的结构也整体外包一层括号——因 ml_parser 的 `atom ::= "(" expr ")"` 允许把
// 任意 `expr`（含 let/if/lambda）当作原子，故被括号包裹后即可作为子表达式 /
// 实参出现并正确回解析（保证往返：Property 2 / R2.5）。
//
// 往返不变式（R2.5）：对任意合法 `Expr` e，
//   parse_ml(lex_ml(print_expr(e))) 去 span 后 == erase_span(e)
// 由任务 2.4 的属性测试守护。`erase_span` 在此提供「去 span 等价比较」的规范化
// 形式：把每个节点的 span 一律置为哨兵 Span{line:0, col:0}（R2.5 / R1.6 /
// R12.7 复用）。

///|
/// 既有冻结 `BinOp`（Add/Sub/Mul/Div）→ 源串算符符号。
fn ml_binop_sym(op : BinOp) -> String {
  match op {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Div => "/"
  }
}

///|
/// `CmpOp` → 源串算符符号。
fn ml_cmpop_sym(op : CmpOp) -> String {
  match op {
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
    Eq_ => "=="
    Ne => "!="
  }
}

///|
/// `LogicOp` → 源串算符符号。
fn ml_logicop_sym(op : LogicOp) -> String {
  match op {
    And => "&&"
    Or => "||"
  }
}

///|
/// 将 `Expr` 打印为 MiniML 源串（R2.4）。
///
/// 完全括号化策略：
/// - 字面量 / 变量为原子，直接打印（`EInt` 以十进制、`EBool` 为 `true`/`false`、
///   `EVar` 为其名字）。生成器产出的整数为非负，故直接 `to_string`。
/// - 二元 / 比较 / 逻辑 / 应用节点一律包裹圆括号，消除优先级 / 结合性歧义。
/// - `if` / `lambda` / `let` / `let rec` 整体外包圆括号，使其可作为原子被
///   `atom ::= "(" expr ")"` 回解析为子表达式 / 实参（保证往返）。
/// - 元组打印为 `(e1, e2, ...)`，与 `atom` 的元组形式对应。
pub fn print_expr(e : Expr) -> String {
  match e {
    EInt(n, _) => n.to_string()
    EBool(b, _) => if b { "true" } else { "false" }
    EVar(s, _) => s
    EArith(op, l, r, _) =>
      "(" + print_expr(l) + " " + ml_binop_sym(op) + " " + print_expr(r) + ")"
    ECmp(op, l, r, _) =>
      "(" + print_expr(l) + " " + ml_cmpop_sym(op) + " " + print_expr(r) + ")"
    ELogic(op, l, r, _) =>
      "(" + print_expr(l) + " " + ml_logicop_sym(op) + " " + print_expr(r) + ")"
    EIf(c, t, f, _) =>
      "(if " +
      print_expr(c) +
      " then " +
      print_expr(t) +
      " else " +
      print_expr(f) +
      ")"
    ELam(x, body, _) => "(fun " + x + " -> " + print_expr(body) + ")"
    EApp(f, a, _) => "(" + print_expr(f) + " " + print_expr(a) + ")"
    ELet(x, e1, e2, _) =>
      "(let " + x + " = " + print_expr(e1) + " in " + print_expr(e2) + ")"
    ELetRec(f, e1, e2, _) =>
      "(let rec " + f + " = " + print_expr(e1) + " in " + print_expr(e2) + ")"
    ETuple(items, _) => {
      let parts = items.map(print_expr)
      "(" + parts.join(", ") + ")"
    }
  }
}

///|
/// 去除全部 span：把每个节点的 span 一律置为哨兵 `Span{line:0, col:0}`，用于
/// 往返等价比较（R2.5）。递归重建整棵语法树，递归进入全部子表达式与元组分量。
pub fn erase_span(e : Expr) -> Expr {
  let z = Span::{ line: 0, col: 0 }
  match e {
    EInt(n, _) => EInt(n, z)
    EBool(b, _) => EBool(b, z)
    EVar(s, _) => EVar(s, z)
    EArith(op, l, r, _) => EArith(op, erase_span(l), erase_span(r), z)
    ECmp(op, l, r, _) => ECmp(op, erase_span(l), erase_span(r), z)
    ELogic(op, l, r, _) => ELogic(op, erase_span(l), erase_span(r), z)
    EIf(c, t, f, _) => EIf(erase_span(c), erase_span(t), erase_span(f), z)
    ELam(x, body, _) => ELam(x, erase_span(body), z)
    EApp(f, a, _) => EApp(erase_span(f), erase_span(a), z)
    ELet(x, e1, e2, _) => ELet(x, erase_span(e1), erase_span(e2), z)
    ELetRec(f, e1, e2, _) => ELetRec(f, erase_span(e1), erase_span(e2), z)
    ETuple(items, _) => ETuple(items.map(erase_span), z)
  }
}
