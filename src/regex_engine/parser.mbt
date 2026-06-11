// parser.mbt —— 正则字符串 → 语法树（`parse_regex`），构建于 @parser_combinator。
//
// 对应任务 6.1 的解析桩：以 @pc 的不可变游标 `Input`（peek / advance / pos）为
// 基座做递归下降解析。`Input` 的不可变性天然支持分组回溯（分支失败只需丢弃
// 推进后的游标）。文法按优先级自低到高分层（design.md 受支持子集 R2.1）：
//
//   alt    := concat ('|' concat)*
//   concat := repeat*                       // 空序列 → Concat([])（空正则）
//   repeat := atom quantifier?
//   quantifier := '*' | '+' | '?' | '{' m (',' n?)? '}'
//   atom   := '(' alt ')' | class | anchor | escaped | char
//   anchor := '^' | '$'
//   class  := '[' '^'? item+ ']'
//
// 非法表达式返回含字符偏移位置的 `ParseError`，且不构造任何自动机（R2.3）：
// 本文件只产出语法树，NFA/DFA 构造属于任务 6.2。

///|
/// 解析正则字符串为语法树（R2.2）；非法时返回含位置的 `ParseError`（R2.3）。
///
/// 成功要求整个输入被完全消费；若顶层解析后仍有残余输入（如多余的 `)`），
/// 返回 `TrailingInput`。
pub fn parse_regex(s : String) -> Result[Regex, ParseError] {
  let input = @pc.Input::from_string(s)
  match parse_alt(input) {
    Err(e) => Err(e)
    Ok((r, rest)) =>
      if rest.is_eof() {
        Ok(r)
      } else {
        Err(TrailingInput(pos=rest.pos.offset))
      }
  }
}

///|
/// 解析层：择一 `a|b|c`。先解析一个 `concat`，随后只要遇到 `|` 便继续。
fn parse_alt(input : @pc.Input) -> Result[(Regex, @pc.Input), ParseError] {
  let (first, rest0) = match parse_concat(input) {
    Err(e) => return Err(e)
    Ok(pair) => pair
  }
  let branches : Array[Regex] = [first]
  let mut cur = rest0
  while cur.peek() == Some('|') {
    let after = cur.advance()
    let (ri, resti) = match parse_concat(after) {
      Err(e) => return Err(e)
      Ok(pair) => pair
    }
    branches.push(ri)
    cur = resti
  }
  if branches.length() == 1 {
    Ok((branches[0], cur))
  } else {
    Ok((Alt(branches), cur))
  }
}

///|
/// 解析层：串接。连续解析 `repeat`，在输入末尾、`|` 或 `)` 处停止。
/// 单元素直接返回该元素；否则包成 `Concat`（空序列亦为 `Concat([])`）。
fn parse_concat(input : @pc.Input) -> Result[(Regex, @pc.Input), ParseError] {
  let parts : Array[Regex] = []
  let mut cur = input
  while true {
    match cur.peek() {
      None => break
      Some('|') => break
      Some(')') => break
      _ => {
        let (r, rest) = match parse_repeat(cur) {
          Err(e) => return Err(e)
          Ok(pair) => pair
        }
        parts.push(r)
        cur = rest
      }
    }
  }
  if parts.length() == 1 {
    Ok((parts[0], cur))
  } else {
    Ok((Concat(parts), cur))
  }
}

///|
/// 解析层：原子 + 可选量词（`*` `+` `?` `{m,n}`）。
fn parse_repeat(input : @pc.Input) -> Result[(Regex, @pc.Input), ParseError] {
  let (atom, rest) = match parse_atom(input) {
    Err(e) => return Err(e)
    Ok(pair) => pair
  }
  match rest.peek() {
    Some('*') => Ok((Star(atom), rest.advance()))
    Some('+') => Ok((Plus(atom), rest.advance()))
    Some('?') => Ok((Opt(atom), rest.advance()))
    Some('{') => parse_brace(atom, rest)
    _ => Ok((atom, rest))
  }
}

///|
/// 计数量词 `{m}` / `{m,}` / `{m,n}`。进入时游标位于 `{`。
fn parse_brace(
  atom : Regex,
  input : @pc.Input,
) -> Result[(Regex, @pc.Input), ParseError] {
  let open = input.pos.offset
  let after_brace = input.advance() // 消费 '{'
  let (m_opt, c1) = read_int(after_brace)
  match m_opt {
    None => Err(InvalidRepeat(pos=open))
    Some(m) =>
      match c1.peek() {
        Some('}') => Ok((Repeat(atom, m, Some(m)), c1.advance()))
        Some(',') => {
          let c2 = c1.advance()
          match c2.peek() {
            Some('}') => Ok((Repeat(atom, m, None), c2.advance()))
            _ => {
              let (n_opt, c3) = read_int(c2)
              match n_opt {
                None => Err(InvalidRepeat(pos=c2.pos.offset))
                Some(n) =>
                  match c3.peek() {
                    Some('}') => Ok((Repeat(atom, m, Some(n)), c3.advance()))
                    _ => Err(InvalidRepeat(pos=c3.pos.offset))
                  }
              }
            }
          }
        }
        _ => Err(InvalidRepeat(pos=c1.pos.offset))
      }
  }
}

///|
/// 解析层：原子（分组 / 字符类 / 锚点 / 转义 / 字面字符）。
fn parse_atom(input : @pc.Input) -> Result[(Regex, @pc.Input), ParseError] {
  let off = input.pos.offset
  match input.peek() {
    None => Err(Unexpected(pos=off, expected=["expression"]))
    Some('(') => {
      let inner = input.advance()
      let (r, rest) = match parse_alt(inner) {
        Err(e) => return Err(e)
        Ok(pair) => pair
      }
      match rest.peek() {
        Some(')') => Ok((Group(r), rest.advance()))
        _ => Err(Unbalanced(pos=rest.pos.offset, what="("))
      }
    }
    Some('[') => parse_class(input)
    Some('^') => Ok((Anchor(Start), input.advance()))
    Some('$') => Ok((Anchor(End), input.advance()))
    Some('*') => Err(DanglingQuantifier(pos=off))
    Some('+') => Err(DanglingQuantifier(pos=off))
    Some('?') => Err(DanglingQuantifier(pos=off))
    Some('{') => Err(DanglingQuantifier(pos=off))
    Some('\\') => {
      let esc = input.advance()
      match esc.peek() {
        Some(c) => Ok((Char(c), esc.advance()))
        None =>
          Err(Unexpected(pos=esc.pos.offset, expected=["escaped character"]))
      }
    }
    // 元字符 ')' / ']' / '}' / '|' 出现在原子位置即为非法（正常路径不会到达
    // ')' 与 '|'，因 concat 已在其前停止；此处兜底以给出明确错误）。
    Some(')') => Err(Unexpected(pos=off, expected=["expression"]))
    Some(']') => Err(Unexpected(pos=off, expected=["expression"]))
    Some('}') => Err(Unexpected(pos=off, expected=["expression"]))
    Some('|') => Err(Unexpected(pos=off, expected=["expression"]))
    Some(c) => Ok((Char(c), input.advance()))
  }
}

///|
/// 解析字符类 `[...]` / `[^...]`。进入时游标位于 `[`。
fn parse_class(input : @pc.Input) -> Result[(Regex, @pc.Input), ParseError] {
  let open = input.pos.offset
  let mut cur = input.advance() // 消费 '['
  let mut negated = false
  match cur.peek() {
    Some('^') => {
      negated = true
      cur = cur.advance()
    }
    _ => ()
  }
  let items : Array[ClassItem] = []
  while true {
    match cur.peek() {
      None => return Err(Unbalanced(pos=open, what="["))
      Some(']') => {
        cur = cur.advance()
        break
      }
      _ => {
        let (lo, c1) = match read_class_char(cur) {
          Err(e) => return Err(e)
          Ok(pair) => pair
        }
        match c1.peek() {
          Some('-') => {
            let dash_next = c1.advance()
            match dash_next.peek() {
              // 紧跟 ']' 的 '-' 视为字面字符（如 "[a-]"）。
              Some(']') => {
                items.push(Single(lo))
                items.push(Single('-'))
                cur = dash_next
              }
              None => return Err(Unbalanced(pos=open, what="["))
              _ => {
                let (hi, c2) = match read_class_char(dash_next) {
                  Err(e) => return Err(e)
                  Ok(pair) => pair
                }
                items.push(Range(lo, hi))
                cur = c2
              }
            }
          }
          _ => {
            items.push(Single(lo))
            cur = c1
          }
        }
      }
    }
  }
  Ok((Class({ negated, items }), cur))
}

///|
/// 读取字符类内的一个字符，支持反斜杠转义（如 `\]`、`\\`、`\-`）。
fn read_class_char(input : @pc.Input) -> Result[(Char, @pc.Input), ParseError] {
  match input.peek() {
    None => Err(Unbalanced(pos=input.pos.offset, what="["))
    Some('\\') => {
      let esc = input.advance()
      match esc.peek() {
        Some(c) => Ok((c, esc.advance()))
        None =>
          Err(Unexpected(pos=esc.pos.offset, expected=["escaped character"]))
      }
    }
    Some(c) => Ok((c, input.advance()))
  }
}

///|
/// 读取连续十进制数字为非负整数；无数字时返回 `None`（不推进有效位）。
fn read_int(input : @pc.Input) -> (Int?, @pc.Input) {
  let mut cur = input
  let mut has = false
  let mut acc = 0
  while true {
    match cur.peek() {
      Some(c) =>
        if c >= '0' && c <= '9' {
          has = true
          acc = acc * 10 + (c.to_int() - '0'.to_int())
          cur = cur.advance()
        } else {
          break
        }
      None => break
    }
  }
  if has {
    (Some(acc), cur)
  } else {
    (None, cur)
  }
}
