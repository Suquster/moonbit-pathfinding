// lexer.mbt —— 源串 → 词法单元序列（`lex`），构建于 @parser_combinator。
//
// 对应任务 15.1 的词法阶段：以 @pc 的不可变游标 `Input`（peek / advance / pos）
// 为基座扫描字符。`@pc.Input::advance` 会自动维护 1 起始的行列号（遇 `\n`
// 换行），因此词法错误可直接取 `input.pos` 得到准确的行列位置（R1.3）。
//
// 本阶段**完整实现**（非桩）：成功时产出 `Array[Token]`；遇非法字符时返回
// `Diagnostic { kind: LexError, line, col, msg }` 且不产生任何后续产物
// （R1.3「不产生 AST」）。

///|
/// 词法分析：将源串切分为词法单元序列（R1.2 的前置阶段）。
///
/// 跳过空白（空格 / 制表 / 回车 / 换行，仅作分隔）；识别整数字面量、标识符
/// （关键字 `let` / `in` 归一为 `KwLet` / `KwIn`）与算术 / 分组 / 赋值符号。
/// 遇到不属于 MiniLet 字母表的字符时，返回含**行列位置**的词法诊断并立即
/// 终止（R1.3）。
pub fn lex(src : String) -> Result[Array[Token], Diagnostic] {
  let tokens : Array[Token] = []
  let mut cur = @pc.Input::from_string(src)
  while !cur.is_eof() {
    let c = match cur.peek() {
      Some(ch) => ch
      None => break
    }
    if is_space(c) {
      cur = cur.advance()
    } else if is_digit(c) {
      let (n, rest) = scan_int(cur)
      tokens.push(IntLit(n))
      cur = rest
    } else if is_alpha(c) {
      let (name, rest) = scan_ident(cur)
      tokens.push(keyword_or_ident(name))
      cur = rest
    } else {
      match symbol_token(c) {
        Some(tok) => {
          tokens.push(tok)
          cur = cur.advance()
        }
        // 非法字符：返回含行列位置的词法诊断，不产生后续产物（R1.3）。
        None =>
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
/// 扫描连续十进制数字为非负整数，返回该整数与推进后的游标。
/// 进入时已知首字符为数字。
fn scan_int(input : @pc.Input) -> (Int, @pc.Input) {
  let mut cur = input
  let mut acc = 0
  while true {
    match cur.peek() {
      Some(c) =>
        if is_digit(c) {
          acc = acc * 10 + (c.to_int() - '0'.to_int())
          cur = cur.advance()
        } else {
          break
        }
      None => break
    }
  }
  (acc, cur)
}

///|
/// 扫描标识符（首字符为字母，后续为字母 / 数字 / 下划线），返回名字与游标。
/// 进入时已知首字符为字母。
fn scan_ident(input : @pc.Input) -> (String, @pc.Input) {
  let mut cur = input
  let mut name = ""
  while true {
    match cur.peek() {
      Some(c) =>
        if is_alpha(c) || is_digit(c) || c == '_' {
          name = name + c.to_string()
          cur = cur.advance()
        } else {
          break
        }
      None => break
    }
  }
  (name, cur)
}

///|
/// 将标识符词素归一为关键字或普通标识符词法单元。
fn keyword_or_ident(name : String) -> Token {
  match name {
    "let" => KwLet
    "in" => KwIn
    _ => Ident(name)
  }
}

///|
/// 将单字符符号映射为词法单元；非符号返回 `None`（交由调用方报词法错误）。
fn symbol_token(c : Char) -> Token? {
  match c {
    '+' => Some(Plus)
    '-' => Some(Minus)
    '*' => Some(Star)
    '/' => Some(Slash)
    '(' => Some(LParen)
    ')' => Some(RParen)
    '=' => Some(Assign)
    _ => None
  }
}

///|
/// 是否为空白字符（空格 / 制表 / 回车 / 换行）。
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
/// 是否为十进制数字 `0`..`9`。
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// 是否为 ASCII 字母（标识符首字符集合）。
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}
