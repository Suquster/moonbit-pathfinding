// ml_parser.mbt —— MiniML 词法单元序列 → 携带 span 的抽象语法树（`parse_ml`）。
//
// 对应任务 2.2（design.md §「3. 语法分析（ml_parser.mbt，R2.2 / R2.3 /
// R8.2）」）：旁路新增的 MiniML 递归下降语法分析器。与既有 MiniLet `parse`
// 不同，本解析器**直接在 `Array[MlToken]` 上**以一个不可变的 token 游标
// （`Int` 索引）递归下降——索引按值传递，分支失败时调用方丢弃推进后的索引即
// 实现「回溯」（无副作用）。如此可为每个节点附带其**起始 token 的 span**，使
// 类型 / 语义诊断可定位到精确源码位置（R1.2 / R8.2）。
//
// 命名约定：本文件与既有冻结的 MiniLet `parser.mbt` 同包，为避免与其
// `parse_expr` / `parse_let` / `parse_add` / `parse_mul` / `parse_atom` /
// `syntax_err` 等同名冲突，全部内部助手统一以 `ml_` 前缀命名，仅公开入口
// `parse_ml` 无前缀。既有文件一行不改，全部能力旁路新增。
//
// 文法（design.md §3，优先级自低到高）：
//   expr     ::= "let" ["rec"] IDENT "=" expr "in" expr
//              | "if" expr "then" expr "else" expr
//              | ("lambda" | "fun") IDENT "->" expr
//              | or_expr
//   or_expr  ::= and_expr ("||" and_expr)*            // 左结合
//   and_expr ::= cmp_expr ("&&" cmp_expr)*            // 左结合
//   cmp_expr ::= add_expr (("<"|"<="|">"|">="|"=="|"!=") add_expr)?  // 非结合
//   add_expr ::= mul_expr (("+"|"-") mul_expr)*       // 左结合
//   mul_expr ::= app_expr (("*"|"/") app_expr)*       // 左结合
//   app_expr ::= atom atom*                           // 函数应用，左结合
//   atom     ::= INT | BOOL | IDENT | "(" expr ")"
//              | "(" expr ("," expr)+ ")"
//
// 错误处理（R2.3 / R8.2）：不符合文法或顶层解析后仍有未消费 token 时，返回
// `Diagnostic { kind: SyntaxError, line, col, msg }`（行列取自出错 token 的
// span；token 已耗尽时退化到最后一个 token 的 span，空输入则为 (0,0)）且不产
// 出语法树。

///|
/// 提取一个词法单元的 span（其起始字符的 1 起始行列）。
fn ml_token_span(tok : MlToken) -> Span {
  match tok {
    TkInt(_, s) => s
    TkBool(_, s) => s
    TkIdent(_, s) => s
    TkKw(_, s) => s
    TkOp(_, s) => s
    TkLParen(s) => s
    TkRParen(s) => s
  }
}

///|
/// 提取一个 `Expr` 节点的 span（即其起始 token 的 span）。用于在构造二元 /
/// 比较 / 逻辑 / 应用节点时，以**左操作数的起始 span**作为整节点的 span
/// （节点 span = 起始 token span）。
fn ml_expr_span(e : Expr) -> Span {
  match e {
    EInt(_, s) => s
    EBool(_, s) => s
    EVar(_, s) => s
    EArith(_, _, _, s) => s
    ECmp(_, _, _, s) => s
    ELogic(_, _, _, s) => s
    EIf(_, _, _, s) => s
    ELam(_, _, s) => s
    EApp(_, _, s) => s
    ELet(_, _, _, s) => s
    ELetRec(_, _, _, s) => s
    ETuple(_, s) => s
  }
}

///|
/// 取 token 游标当前位置的词法单元（越界返回 `None`）。
fn ml_peek_tok(tokens : Array[MlToken], pos : Int) -> MlToken? {
  if pos >= 0 && pos < tokens.length() {
    Some(tokens[pos])
  } else {
    None
  }
}

///|
/// 在 `pos` 处构造语法诊断（R8.2）：行列取自该位置 token 的 span；token 已
/// 耗尽时退化到最后一个 token 的 span；空输入则为 (0, 0)。
fn ml_syntax_err(
  tokens : Array[MlToken],
  pos : Int,
  msg : String,
) -> Diagnostic {
  let (line, col) = if pos >= 0 && pos < tokens.length() {
    let s = ml_token_span(tokens[pos])
    (s.line, s.col)
  } else if tokens.length() > 0 {
    let s = ml_token_span(tokens[tokens.length() - 1])
    (s.line, s.col)
  } else {
    (0, 0)
  }
  Diagnostic::new(SyntaxError, line, col, msg)
}

///|
/// 判断某词法单元是否可**起始**一个原子（INT / BOOL / IDENT / `(`），用于
/// `app_expr` 贪婪收集实参。
fn ml_starts_atom(tok : MlToken?) -> Bool {
  match tok {
    Some(TkInt(_, _)) => true
    Some(TkBool(_, _)) => true
    Some(TkIdent(_, _)) => true
    Some(TkLParen(_)) => true
    _ => false
  }
}

///|
/// 比较算符文本 → `CmpOp`（非比较算符返回 `None`）。
fn ml_cmp_of_string(op : String) -> CmpOp? {
  match op {
    "<" => Some(Lt)
    "<=" => Some(Le)
    ">" => Some(Gt)
    ">=" => Some(Ge)
    "==" => Some(Eq_)
    "!=" => Some(Ne)
    _ => None
  }
}

///|
/// MiniML 语法分析：词法单元序列 → 携带 span 的 `Expr`（R2.2）。
///
/// 从位置 0 解析单个 `expr`；解析后若仍有未消费 token，返回 `SyntaxError`
/// （携带残余 token 位置）且不产树（R2.3）。空输入返回 `SyntaxError`。
pub fn parse_ml(tokens : Array[MlToken]) -> Result[Expr, Diagnostic] {
  if tokens.length() == 0 {
    return Err(
      Diagnostic::new(SyntaxError, 0, 0, "空输入：无可解析的 token"),
    )
  }
  match ml_parse_expr(tokens, 0) {
    Err(d) => Err(d)
    Ok((e, pos)) =>
      if pos == tokens.length() {
        Ok(e)
      } else {
        Err(
          ml_syntax_err(tokens, pos, "顶层解析后存在未消费的 token"),
        )
      }
  }
}

///|
/// 解析层：`expr`。按起始 token 分派到 `let` / `if` / `lambda`(`fun`) 三种带
/// 关键字的形式，否则下降到 `or_expr`（最低优先级的运算层）。
fn ml_parse_expr(
  tokens : Array[MlToken],
  pos : Int,
) -> Result[(Expr, Int), Diagnostic] {
  match ml_peek_tok(tokens, pos) {
    Some(TkKw("let", span)) => ml_parse_let(tokens, pos, span)
    Some(TkKw("if", span)) => ml_parse_if(tokens, pos, span)
    Some(TkKw("lambda", span)) | Some(TkKw("fun", span)) =>
      ml_parse_lambda(tokens, pos, span)
    _ => ml_parse_or(tokens, pos)
  }
}

///|
/// 解析 `let ["rec"] IDENT "=" expr "in" expr`。进入时 `pos` 指向 `let`，
/// `span` 为 `let` 的 span（整节点 span）。`rec` 存在则产 `ELetRec`，否则
/// `ELet`。
fn ml_parse_let(
  tokens : Array[MlToken],
  pos : Int,
  span : Span,
) -> Result[(Expr, Int), Diagnostic] {
  // 可选 `rec`。
  let (is_rec, p_after_rec) = match ml_peek_tok(tokens, pos + 1) {
    Some(TkKw("rec", _)) => (true, pos + 2)
    _ => (false, pos + 1)
  }
  // 绑定名（标识符）。
  let (name, p_after_name) = match ml_peek_tok(tokens, p_after_rec) {
    Some(TkIdent(n, _)) => (n, p_after_rec + 1)
    _ =>
      return Err(
        ml_syntax_err(tokens, p_after_rec, "期望标识符（let 绑定名）"),
      )
  }
  // `=`。
  let p_after_eq = match ml_peek_tok(tokens, p_after_name) {
    Some(TkOp("=", _)) => p_after_name + 1
    _ => return Err(ml_syntax_err(tokens, p_after_name, "期望 '='"))
  }
  // 被绑定表达式。
  let (bound, p_after_bound) = match ml_parse_expr(tokens, p_after_eq) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  // `in`。
  let p_after_in = match ml_peek_tok(tokens, p_after_bound) {
    Some(TkKw("in", _)) => p_after_bound + 1
    _ =>
      return Err(ml_syntax_err(tokens, p_after_bound, "期望关键字 'in'"))
  }
  // body 表达式。
  let (body, p_after_body) = match ml_parse_expr(tokens, p_after_in) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let node = if is_rec {
    ELetRec(name, bound, body, span)
  } else {
    ELet(name, bound, body, span)
  }
  Ok((node, p_after_body))
}

///|
/// 解析 `if expr "then" expr "else" expr`。进入时 `pos` 指向 `if`，`span` 为
/// `if` 的 span。
fn ml_parse_if(
  tokens : Array[MlToken],
  pos : Int,
  span : Span,
) -> Result[(Expr, Int), Diagnostic] {
  let (cond, p1) = match ml_parse_expr(tokens, pos + 1) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let p_after_then = match ml_peek_tok(tokens, p1) {
    Some(TkKw("then", _)) => p1 + 1
    _ => return Err(ml_syntax_err(tokens, p1, "期望关键字 'then'"))
  }
  let (then_e, p2) = match ml_parse_expr(tokens, p_after_then) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let p_after_else = match ml_peek_tok(tokens, p2) {
    Some(TkKw("else", _)) => p2 + 1
    _ => return Err(ml_syntax_err(tokens, p2, "期望关键字 'else'"))
  }
  let (else_e, p3) = match ml_parse_expr(tokens, p_after_else) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  Ok((EIf(cond, then_e, else_e, span), p3))
}

///|
/// 解析 `("lambda" | "fun") IDENT "->" expr`。进入时 `pos` 指向关键字，`span`
/// 为该关键字的 span。
fn ml_parse_lambda(
  tokens : Array[MlToken],
  pos : Int,
  span : Span,
) -> Result[(Expr, Int), Diagnostic] {
  let (param, p_after_param) = match ml_peek_tok(tokens, pos + 1) {
    Some(TkIdent(n, _)) => (n, pos + 2)
    _ =>
      return Err(
        ml_syntax_err(tokens, pos + 1, "期望标识符（函数形参）"),
      )
  }
  let p_after_arrow = match ml_peek_tok(tokens, p_after_param) {
    Some(TkOp("->", _)) => p_after_param + 1
    _ => return Err(ml_syntax_err(tokens, p_after_param, "期望 '->'"))
  }
  let (body, p_after_body) = match ml_parse_expr(tokens, p_after_arrow) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  Ok((ELam(param, body, span), p_after_body))
}

///|
/// 解析层：`or_expr ::= and_expr ("||" and_expr)*`（左结合）。
fn ml_parse_or(
  tokens : Array[MlToken],
  pos : Int,
) -> Result[(Expr, Int), Diagnostic] {
  let (first, p0) = match ml_parse_and(tokens, pos) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let mut acc = first
  let mut cur = p0
  while (match ml_peek_tok(tokens, cur) {
          Some(TkOp("||", _)) => true
          _ => false
        }) {
    let (right, p) = match ml_parse_and(tokens, cur + 1) {
      Err(d) => return Err(d)
      Ok(pair) => pair
    }
    acc = ELogic(Or, acc, right, ml_expr_span(acc))
    cur = p
  }
  Ok((acc, cur))
}

///|
/// 解析层：`and_expr ::= cmp_expr ("&&" cmp_expr)*`（左结合）。
fn ml_parse_and(
  tokens : Array[MlToken],
  pos : Int,
) -> Result[(Expr, Int), Diagnostic] {
  let (first, p0) = match ml_parse_cmp(tokens, pos) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let mut acc = first
  let mut cur = p0
  while (match ml_peek_tok(tokens, cur) {
          Some(TkOp("&&", _)) => true
          _ => false
        }) {
    let (right, p) = match ml_parse_cmp(tokens, cur + 1) {
      Err(d) => return Err(d)
      Ok(pair) => pair
    }
    acc = ELogic(And, acc, right, ml_expr_span(acc))
    cur = p
  }
  Ok((acc, cur))
}

///|
/// 解析层：`cmp_expr ::= add_expr (CMP add_expr)?`（非结合，最多一个比较）。
fn ml_parse_cmp(
  tokens : Array[MlToken],
  pos : Int,
) -> Result[(Expr, Int), Diagnostic] {
  let (left, p0) = match ml_parse_add(tokens, pos) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  match ml_peek_tok(tokens, p0) {
    Some(TkOp(op, _)) =>
      match ml_cmp_of_string(op) {
        Some(cop) => {
          let (right, p1) = match ml_parse_add(tokens, p0 + 1) {
            Err(d) => return Err(d)
            Ok(pair) => pair
          }
          Ok((ECmp(cop, left, right, ml_expr_span(left)), p1))
        }
        None => Ok((left, p0))
      }
    _ => Ok((left, p0))
  }
}

///|
/// 解析层：`add_expr ::= mul_expr (("+"|"-") mul_expr)*`（左结合）。
fn ml_parse_add(
  tokens : Array[MlToken],
  pos : Int,
) -> Result[(Expr, Int), Diagnostic] {
  let (first, p0) = match ml_parse_mul(tokens, pos) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let mut acc = first
  let mut cur = p0
  for ;; {
    let op = match ml_peek_tok(tokens, cur) {
      Some(TkOp("+", _)) => Add
      Some(TkOp("-", _)) => Sub
      _ => break
    }
    let (right, p) = match ml_parse_mul(tokens, cur + 1) {
      Err(d) => return Err(d)
      Ok(pair) => pair
    }
    acc = EArith(op, acc, right, ml_expr_span(acc))
    cur = p
  }
  Ok((acc, cur))
}

///|
/// 解析层：`mul_expr ::= app_expr (("*"|"/") app_expr)*`（左结合）。
fn ml_parse_mul(
  tokens : Array[MlToken],
  pos : Int,
) -> Result[(Expr, Int), Diagnostic] {
  let (first, p0) = match ml_parse_app(tokens, pos) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let mut acc = first
  let mut cur = p0
  for ;; {
    let op = match ml_peek_tok(tokens, cur) {
      Some(TkOp("*", _)) => Mul
      Some(TkOp("/", _)) => Div
      _ => break
    }
    let (right, p) = match ml_parse_app(tokens, cur + 1) {
      Err(d) => return Err(d)
      Ok(pair) => pair
    }
    acc = EArith(op, acc, right, ml_expr_span(acc))
    cur = p
  }
  Ok((acc, cur))
}

///|
/// 解析层：`app_expr ::= atom atom*`（函数应用，左结合）。先解析一个原子，
/// 再贪婪地把后续每个「可起始原子」的 token 解析为实参，构造左结合 `EApp`。
fn ml_parse_app(
  tokens : Array[MlToken],
  pos : Int,
) -> Result[(Expr, Int), Diagnostic] {
  let (first, p0) = match ml_parse_atom(tokens, pos) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let mut acc = first
  let mut cur = p0
  while ml_starts_atom(ml_peek_tok(tokens, cur)) {
    let (arg, p) = match ml_parse_atom(tokens, cur) {
      Err(d) => return Err(d)
      Ok(pair) => pair
    }
    acc = EApp(acc, arg, ml_expr_span(acc))
    cur = p
  }
  Ok((acc, cur))
}

///|
/// 解析层：`atom ::= INT | BOOL | IDENT | "(" expr ")" | "(" expr ("," expr)+ ")"`。
///
/// 括号形式：先解析内层 `expr`；若紧随 `,` 则解析 ≥2 元元组并以左括号 span 作
/// 为 `ETuple` 的 span；否则期望 `)` 并返回内层表达式（分组，沿用内层 span）。
fn ml_parse_atom(
  tokens : Array[MlToken],
  pos : Int,
) -> Result[(Expr, Int), Diagnostic] {
  match ml_peek_tok(tokens, pos) {
    Some(TkInt(n, s)) => Ok((EInt(n, s), pos + 1))
    Some(TkBool(b, s)) => Ok((EBool(b, s), pos + 1))
    Some(TkIdent(name, s)) => Ok((EVar(name, s), pos + 1))
    Some(TkLParen(s)) => {
      let (first, p1) = match ml_parse_expr(tokens, pos + 1) {
        Err(d) => return Err(d)
        Ok(pair) => pair
      }
      match ml_peek_tok(tokens, p1) {
        Some(TkRParen(_)) => Ok((first, p1 + 1))
        Some(TkOp(",", _)) => {
          // 元组：收集 ≥2 个分量。
          let elems = [first]
          let mut cur = p1
          while (match ml_peek_tok(tokens, cur) {
                  Some(TkOp(",", _)) => true
                  _ => false
                }) {
            let (e, p) = match ml_parse_expr(tokens, cur + 1) {
              Err(d) => return Err(d)
              Ok(pair) => pair
            }
            elems.push(e)
            cur = p
          }
          match ml_peek_tok(tokens, cur) {
            Some(TkRParen(_)) => Ok((ETuple(elems, s), cur + 1))
            _ => Err(ml_syntax_err(tokens, cur, "元组期望 ')'"))
          }
        }
        _ => Err(ml_syntax_err(tokens, p1, "期望 ')' 或 ','"))
      }
    }
    _ =>
      Err(
        ml_syntax_err(
          tokens, pos, "期望原子表达式（整数 / 布尔 / 标识符 / '('）",
        ),
      )
  }
}
