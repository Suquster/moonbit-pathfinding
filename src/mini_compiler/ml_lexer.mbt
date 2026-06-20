// ml_lexer.mbt —— MiniML 源串 → 携带 span 的词法单元序列（`lex_ml`）。
//
// 对应任务 2.1（design.md §「2. 词法分析（ml_lexer.mbt，R2.1 / R8.1）」）：
// 旁路新增的 MiniML 词法器，构建于 @parser_combinator 的不可变游标 `@pc.Input`
// （`peek` / `advance` / `pos`，1 起始行列；`advance` 遇 `\n` 自动换行）。本文件
// **复用** lexer.mbt（同包）既有的扫描助手 `scan_int` / `scan_ident` /
// `is_alpha` / `is_digit` / `is_space`，不重复实现，亦**不修改**任何既有文件。
//
// 与既有 `lex`（MiniLet）相比，MiniML 词法表更丰富：布尔字面量、比较 / 逻辑 /
// 箭头等多字符算符与更多关键字，且每个 token 携带其起始位置的 `Span`（R1.2），
// 供 parse_ml 为节点附 span、供诊断定位。
//
// 错误处理（R8.1）：遇到不属于 MiniML 字母表的字符，返回
// `Diagnostic { kind: LexError, line, col, msg }`（行列指向该字符）并立即终止，
// 不产出任何后续 token。

///|
/// MiniML 词法分析：将源串切分为携带 span 的词法单元序列（R2.1 的前置阶段）。
///
/// 跳过空白（复用 `is_space`，仅作分隔）；识别整数字面量（`scan_int`）、标识符
/// （`scan_ident`，关键字 / 布尔归一）与算符 / 括号。多字符算符
/// （`<=` `>=` `==` `!=` `&&` `||` `->`）按**最长匹配**扫描。每个 token 的 span
/// 取其**起始字符**的行列（`cur.pos`）。遇非 MiniML 字母表字符时，返回含行列
/// 位置的词法诊断并立即终止（R8.1），不产出后续 token。
///
/// token 映射：
/// - 整数            → `TkInt(n, span)`
/// - `true`/`false`  → `TkBool(b, span)`
/// - `let`/`rec`/`in`/`if`/`then`/`else`/`fun`/`lambda` → `TkKw(name, span)`
/// - 其他标识符      → `TkIdent(name, span)`
/// - `+ - * / < <= > >= == != && || ->` 及 `,` → `TkOp(text, span)`
/// - `(`             → `TkLParen(span)`
/// - `)`             → `TkRParen(span)`
pub fn lex_ml(src : String) -> Result[Array[MlToken], Diagnostic] {
  let tokens : Array[MlToken] = []
  let mut cur = @pc.Input::from_string(src)
  while !cur.is_eof() {
    let c = match cur.peek() {
      Some(ch) => ch
      None => break
    }
    // 每个 token 的 span 锚定到其起始字符的行列（1 起始）。
    let span = Span::{ line: cur.pos.line, col: cur.pos.col }
    if is_space(c) {
      cur = cur.advance()
    } else if is_digit(c) {
      let (n, rest) = scan_int(cur)
      tokens.push(TkInt(n, span))
      cur = rest
    } else if is_alpha(c) {
      let (name, rest) = scan_ident(cur)
      tokens.push(classify_ident(name, span))
      cur = rest
    } else {
      // 算符 / 括号：对可起多字符算符的前导字符做最长匹配（peek 下一字符）。
      let next = cur.advance().peek()
      match c {
        '+' => {
          tokens.push(TkOp("+", span))
          cur = cur.advance()
        }
        '*' => {
          tokens.push(TkOp("*", span))
          cur = cur.advance()
        }
        '/' => {
          tokens.push(TkOp("/", span))
          cur = cur.advance()
        }
        ',' => {
          tokens.push(TkOp(",", span))
          cur = cur.advance()
        }
        '(' => {
          tokens.push(TkLParen(span))
          cur = cur.advance()
        }
        ')' => {
          tokens.push(TkRParen(span))
          cur = cur.advance()
        }
        '-' =>
          // `->`（箭头）最长匹配，否则单字符 `-`。
          if next == Some('>') {
            tokens.push(TkOp("->", span))
            cur = cur.advance().advance()
          } else {
            tokens.push(TkOp("-", span))
            cur = cur.advance()
          }
        '<' =>
          if next == Some('=') {
            tokens.push(TkOp("<=", span))
            cur = cur.advance().advance()
          } else {
            tokens.push(TkOp("<", span))
            cur = cur.advance()
          }
        '>' =>
          if next == Some('=') {
            tokens.push(TkOp(">=", span))
            cur = cur.advance().advance()
          } else {
            tokens.push(TkOp(">", span))
            cur = cur.advance()
          }
        '=' =>
          // `==` 为比较算符；单 `=` 为绑定算符（`let x = e`）。
          if next == Some('=') {
            tokens.push(TkOp("==", span))
            cur = cur.advance().advance()
          } else {
            tokens.push(TkOp("=", span))
            cur = cur.advance()
          }
        '!' =>
          // 仅 `!=` 合法；孤立 `!` 非法。
          if next == Some('=') {
            tokens.push(TkOp("!=", span))
            cur = cur.advance().advance()
          } else {
            return Err(
              Diagnostic::new(
                LexError,
                cur.pos.line,
                cur.pos.col,
                "非法字符 '\{c}'",
              ),
            )
          }
        '&' =>
          // 仅 `&&` 合法；孤立 `&` 非法。
          if next == Some('&') {
            tokens.push(TkOp("&&", span))
            cur = cur.advance().advance()
          } else {
            return Err(
              Diagnostic::new(
                LexError,
                cur.pos.line,
                cur.pos.col,
                "非法字符 '\{c}'",
              ),
            )
          }
        '|' =>
          // 仅 `||` 合法；孤立 `|` 非法。
          if next == Some('|') {
            tokens.push(TkOp("||", span))
            cur = cur.advance().advance()
          } else {
            return Err(
              Diagnostic::new(
                LexError,
                cur.pos.line,
                cur.pos.col,
                "非法字符 '\{c}'",
              ),
            )
          }
        // 非 MiniML 字母表字符：返回含行列位置的词法诊断并终止（R8.1）。
        _ =>
          return Err(
            Diagnostic::new(
              LexError,
              cur.pos.line,
              cur.pos.col,
              "非法字符 '\{c}'",
            ),
          )
      }
    }
  }
  Ok(tokens)
}

///|
/// 将标识符词素归一为关键字 / 布尔 / 普通标识符词法单元（携带 span）。
///
/// `true` / `false` 归一为 `TkBool`；`let` / `rec` / `in` / `if` / `then` /
/// `else` / `fun` / `lambda` 归一为 `TkKw`；其余为 `TkIdent`。
fn classify_ident(name : String, span : Span) -> MlToken {
  match name {
    "true" => TkBool(true, span)
    "false" => TkBool(false, span)
    "let" | "rec" | "in" | "if" | "then" | "else" | "fun" | "lambda" =>
      TkKw(name, span)
    _ => TkIdent(name, span)
  }
}
