// parser.mbt —— 词法单元序列 → 抽象语法树（`parse`），构建于 @parser_combinator。
//
// 对应任务 15.1 的语法阶段（design.md `parse(tokens : Array[Token]) ->
// Result[Ast, Diagnostic]`）。与 regex_engine 的 `parse_regex` 一致，本解析器
// 构建于 @pc 的不可变游标 `Input`（peek / advance / pos）之上做递归下降——
// `Input` 的不可变性天然支持括号分组的回溯（分支失败只需丢弃推进后的游标），
// 其 `Pos` 提供 1 起始的行列号，使语法诊断携带准确位置（R1.3）。
//
// 由于 @parser_combinator 的 `Input` 以字符为单元，本阶段采用「无扫描器
// （scannerless）」策略：先由 `tokens_to_source` 将词法单元序列还原为规范
// 源串，再在该源串的 @pc.Input 上递归下降。词法单元的扫描复用 lexer.mbt 中
// 的 `scan_int` / `scan_ident` 等纯助手（同包共享，避免重复实现）。
//
// 文法（见 moon.pkg，优先级自低到高）：
//   expr ::= "let" IDENT "=" expr "in" expr | add
//   add  ::= mul (("+" | "-") mul)*
//   mul  ::= atom (("*" | "/") atom)*
//   atom ::= INT | IDENT | "(" expr ")"
//
// 语法错误返回 `Diagnostic { kind: SyntaxError, line, col, msg }` 且不产生
// AST（R1.3）。位置取自规范源串上的 @pc.Pos。

///|
/// 语法分析：将词法单元序列解析为抽象语法树（R1.2）；不符合文法时返回含
/// 行列位置的语法诊断（R1.3）。
///
/// 要求整个输入被完全消费：顶层表达式解析后若仍有残余（如多余的 `)`），
/// 返回 `SyntaxError`。
pub fn parse(tokens : Array[Token]) -> Result[Ast, Diagnostic] {
  let src = tokens_to_source(tokens)
  let input = @pc.Input::from_string(src)
  match parse_expr(input) {
    Err(d) => Err(d)
    Ok((ast, rest)) => {
      let after = skip_ws(rest)
      if after.is_eof() {
        Ok(ast)
      } else {
        Err(syntax_err(after, "多余的输入"))
      }
    }
  }
}

///|
/// 将词法单元序列还原为以单空格分隔的规范源串（供 @pc.Input 递归下降）。
fn tokens_to_source(tokens : Array[Token]) -> String {
  let mut acc = ""
  for i, t in tokens {
    if i > 0 {
      acc = acc + " "
    }
    acc = acc + token_lexeme(t)
  }
  acc
}

///|
/// 单个词法单元的规范词素（lexeme）文本。
fn token_lexeme(t : Token) -> String {
  match t {
    IntLit(n) => n.to_string()
    Ident(s) => s
    KwLet => "let"
    KwIn => "in"
    Plus => "+"
    Minus => "-"
    Star => "*"
    Slash => "/"
    LParen => "("
    RParen => ")"
    Assign => "="
  }
}

///|
/// 解析层：表达式。`let` 前瞻——若下一标识符为关键字 `let` 则解析 let 绑定，
/// 否则下降到 `add`（加减层）。
fn parse_expr(input : @pc.Input) -> Result[(Ast, @pc.Input), Diagnostic] {
  let cur = skip_ws(input)
  match cur.peek() {
    Some(c) =>
      if is_alpha(c) {
        let (name, _) = scan_ident(cur)
        if name == "let" {
          return parse_let(cur)
        }
      }
    None => ()
  }
  parse_add(cur)
}

///|
/// 解析 `let IDENT = expr in expr`。进入时游标位于关键字 `let`。
fn parse_let(input : @pc.Input) -> Result[(Ast, @pc.Input), Diagnostic] {
  let (_, after_let) = scan_ident(input) // 消费 "let"
  let c1 = skip_ws(after_let)
  // 期望绑定名（标识符，且不得为关键字）。
  let (name, after_name) = match c1.peek() {
    Some(c) =>
      if is_alpha(c) {
        scan_ident(c1)
      } else {
        return Err(syntax_err(c1, "期望标识符（let 绑定名）"))
      }
    None => return Err(syntax_err(c1, "期望标识符（let 绑定名）"))
  }
  if name == "let" || name == "in" {
    return Err(syntax_err(c1, "关键字 '\{name}' 不能作为绑定名"))
  }
  let c2 = skip_ws(after_name)
  // 期望 '='。
  let c3 = match c2.peek() {
    Some('=') => c2.advance()
    _ => return Err(syntax_err(c2, "期望 '='"))
  }
  // 解析被绑定表达式。
  let (bound, after_bound) = match parse_expr(c3) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let c4 = skip_ws(after_bound)
  // 期望关键字 'in'。
  let after_in = match c4.peek() {
    Some(c) =>
      if is_alpha(c) {
        let (kw, rest) = scan_ident(c4)
        if kw == "in" {
          rest
        } else {
          return Err(syntax_err(c4, "期望关键字 'in'"))
        }
      } else {
        return Err(syntax_err(c4, "期望关键字 'in'"))
      }
    None => return Err(syntax_err(c4, "期望关键字 'in'"))
  }
  // 解析 body。
  let (body, after_body) = match parse_expr(after_in) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  Ok((Let(name, bound, body), after_body))
}

///|
/// 解析层：加减（左结合）。
fn parse_add(input : @pc.Input) -> Result[(Ast, @pc.Input), Diagnostic] {
  let (first, rest0) = match parse_mul(input) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let mut acc = first
  let mut cur = rest0
  while true {
    let c = skip_ws(cur)
    let op = match c.peek() {
      Some('+') => Add
      Some('-') => Sub
      _ => break
    }
    let (right, rest) = match parse_mul(c.advance()) {
      Err(d) => return Err(d)
      Ok(pair) => pair
    }
    acc = Bin(op, acc, right)
    cur = rest
  }
  Ok((acc, cur))
}

///|
/// 解析层：乘除（左结合，优先级高于加减）。
fn parse_mul(input : @pc.Input) -> Result[(Ast, @pc.Input), Diagnostic] {
  let (first, rest0) = match parse_atom(input) {
    Err(d) => return Err(d)
    Ok(pair) => pair
  }
  let mut acc = first
  let mut cur = rest0
  while true {
    let c = skip_ws(cur)
    let op = match c.peek() {
      Some('*') => Mul
      Some('/') => Div
      _ => break
    }
    let (right, rest) = match parse_atom(c.advance()) {
      Err(d) => return Err(d)
      Ok(pair) => pair
    }
    acc = Bin(op, acc, right)
    cur = rest
  }
  Ok((acc, cur))
}

///|
/// 解析层：原子（整数字面量 / 变量 / 括号分组）。
fn parse_atom(input : @pc.Input) -> Result[(Ast, @pc.Input), Diagnostic] {
  let cur = skip_ws(input)
  match cur.peek() {
    None => Err(syntax_err(cur, "期望表达式"))
    Some(c) =>
      if is_digit(c) {
        let (n, rest) = scan_int(cur)
        Ok((Int(n), rest))
      } else if is_alpha(c) {
        let (name, rest) = scan_ident(cur)
        if name == "let" || name == "in" {
          Err(syntax_err(cur, "意外的关键字 '\{name}'"))
        } else {
          Ok((Var(name), rest))
        }
      } else if c == '(' {
        let (inner, rest) = match parse_expr(cur.advance()) {
          Err(d) => return Err(d)
          Ok(pair) => pair
        }
        let after = skip_ws(rest)
        match after.peek() {
          Some(')') => Ok((inner, after.advance()))
          _ => Err(syntax_err(after, "期望 ')'"))
        }
      } else {
        Err(syntax_err(cur, "期望表达式"))
      }
  }
}

///|
/// 跳过空白字符，返回推进后的游标（@pc.Input 不可变，原样安全丢弃旧游标）。
fn skip_ws(input : @pc.Input) -> @pc.Input {
  let mut cur = input
  while true {
    match cur.peek() {
      Some(c) => if is_space(c) { cur = cur.advance() } else { break }
      None => break
    }
  }
  cur
}

///|
/// 由当前游标位置构造语法诊断（携带 @pc.Pos 的 1 起始行列号）。
fn syntax_err(input : @pc.Input, msg : String) -> Diagnostic {
  Diagnostic::new(SyntaxError, input.pos.line, input.pos.col, msg)
}
