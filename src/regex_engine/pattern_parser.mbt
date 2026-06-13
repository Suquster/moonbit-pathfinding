// pattern_parser.mbt —— 富语法树解析器 `parse_pattern`（旗舰深化）。
//
// 对应 design.md §4.1（R1/R3/R5/R6）。本文件为**新增**，与既有 `parse_regex`
// 「同一括号、两套解析器、互不干扰」：`parse_pattern` 把模式字符串解析为富
// 语法树 `Ast`，支持捕获 / 命名 / 非捕获组、惰性量词、零宽断言、前瞻、预定义
// 字符类、点号与内联标志。
//
// 复用既有 @pc.Input 不可变游标（peek/advance/pos/is_eof，分支失败丢弃推进的
// 游标天然回溯）与既有 parser.mbt 的包内私有原语 `read_int`、nfa.mbt 的
// `char_set_of_char` / `normalize_intervals`。错误一律映射到既有 `ParseError`
// （不扩容枚举，R1.7）；解析失败不构造任何程序 / 自动机。
//
// 文法（design.md §4.1）：
//   alt     := concat ('|' concat)*
//   concat  := piece*
//   piece   := atom quantifier?
//   quantifier := ('*'|'+'|'?'|'{' m (',' n?)? '}') '?'?      // 末尾 '?' 标记惰性
//   atom    := group | class | predef | anchor | wordb | look | escaped | char
//   group   := '(' ( '?:' | '?<' name '>' | '?P<' name '>' | '?' flags (':')? )? alt ')'
//   look    := '(' ('?=' | '?!') alt ')'

///|
/// 解析期可变状态：捕获组编号计数器、命名组映射与当前作用域标志。
priv struct PState {
  mut next_group : Int
  names : Map[String, Int]
  mut flags : Flags
}

///|
/// 解析模式字符串为富语法树（R1/R3/R5/R6）；非法时返回含位置的 `ParseError`
/// （R1.7），且不构造任何程序 / 自动机。要求整个输入被完全消费。
pub fn parse_pattern(
  pattern : String,
  flags? : Flags = Flags::default(),
) -> Result[Ast, ParseError] {
  let st : PState = { next_group: 1, names: Map([]), flags }
  let input = @pc.Input::from_string(pattern)
  match p_alt(st, input) {
    Err(e) => Err(e)
    Ok((a, rest)) =>
      if rest.is_eof() {
        Ok(a)
      } else {
        Err(TrailingInput(pos=rest.pos.offset))
      }
  }
}

///|
/// 择一 `a|b|c`。
fn p_alt(
  st : PState,
  input : @pc.Input,
) -> Result[(Ast, @pc.Input), ParseError] {
  let (first, rest0) = match p_concat(st, input) {
    Err(e) => return Err(e)
    Ok(pair) => pair
  }
  let branches : Array[Ast] = [first]
  let mut cur = rest0
  while cur.peek() == Some('|') {
    let after = cur.advance()
    let (ri, resti) = match p_concat(st, after) {
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
/// 串接：连续解析 piece，在 EOF、`|`、`)` 处停止。空序列 → `Empty`。
fn p_concat(
  st : PState,
  input : @pc.Input,
) -> Result[(Ast, @pc.Input), ParseError] {
  let parts : Array[Ast] = []
  let mut cur = input
  while true {
    match cur.peek() {
      None => break
      Some('|') => break
      Some(')') => break
      _ => {
        let (a, rest) = match p_piece(st, cur) {
          Err(e) => return Err(e)
          Ok(pair) => pair
        }
        // 内联标志组（bare `(?ims)`）产出 `Empty`，从串接中略去。
        match a {
          Empty => ()
          _ => parts.push(a)
        }
        cur = rest
      }
    }
  }
  if parts.length() == 0 {
    Ok((Empty, cur))
  } else if parts.length() == 1 {
    Ok((parts[0], cur))
  } else {
    Ok((Concat(parts), cur))
  }
}

///|
/// 原子 + 可选量词（`*`/`+`/`?`/`{m,n}`，末尾 `?` 标记惰性）。
fn p_piece(
  st : PState,
  input : @pc.Input,
) -> Result[(Ast, @pc.Input), ParseError] {
  let (atom, rest) = match p_atom(st, input) {
    Err(e) => return Err(e)
    Ok(pair) => pair
  }
  match rest.peek() {
    Some('*') => p_quant_suffix(atom, 0, None, rest.advance())
    Some('+') => p_quant_suffix(atom, 1, None, rest.advance())
    Some('?') => p_quant_suffix(atom, 0, Some(1), rest.advance())
    Some('{') =>
      match parse_brace_pattern(rest) {
        Err(e) => Err(e)
        Ok((m, hi, after)) => p_quant_suffix(atom, m, hi, after)
      }
    _ => Ok((atom, rest))
  }
}

///|
/// 量词后缀的惰性判定：紧跟 `?` 置 `greedy=false`，否则 `greedy=true`（R3.1）。
fn p_quant_suffix(
  node : Ast,
  min : Int,
  max : Int?,
  input : @pc.Input,
) -> Result[(Ast, @pc.Input), ParseError] {
  match input.peek() {
    Some('?') => Ok((Repeat(node~, min~, max~, greedy=false), input.advance()))
    _ => Ok((Repeat(node~, min~, max~, greedy=true), input))
  }
}

///|
/// 计数量词 `{m}` / `{m,}` / `{m,n}`（进入时游标位于 `{`）；复用 parser.mbt 的
/// 包内私有 `read_int`，错误映射到既有 `InvalidRepeat`。
fn parse_brace_pattern(
  input : @pc.Input,
) -> Result[(Int, Int?, @pc.Input), ParseError] {
  let open = input.pos.offset
  let after = input.advance() // 消费 '{'
  let (m_opt, c1) = read_int(after)
  match m_opt {
    None => Err(InvalidRepeat(pos=open))
    Some(m) =>
      match c1.peek() {
        Some('}') => Ok((m, Some(m), c1.advance()))
        Some(',') => {
          let c2 = c1.advance()
          match c2.peek() {
            Some('}') => Ok((m, None, c2.advance()))
            _ => {
              let (n_opt, c3) = read_int(c2)
              match n_opt {
                None => Err(InvalidRepeat(pos=c2.pos.offset))
                Some(n) =>
                  match c3.peek() {
                    Some('}') => Ok((m, Some(n), c3.advance()))
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
/// 原子：分组 / 字符类 / 点号 / 锚点 / 转义 / 字面字符。
fn p_atom(
  st : PState,
  input : @pc.Input,
) -> Result[(Ast, @pc.Input), ParseError] {
  let off = input.pos.offset
  match input.peek() {
    None => Err(Unexpected(pos=off, expected=["expression"]))
    Some('(') => p_group(st, input)
    Some('[') => p_class(st, input)
    Some('.') => Ok((Set(st.flags.dot_set()), input.advance()))
    Some('^') =>
      Ok(
        (
          Assert(if st.flags.multiline { LineStart } else { TextStart }),
          input.advance(),
        ),
      )
    Some('$') =>
      Ok(
        (
          Assert(if st.flags.multiline { LineEnd } else { TextEnd }),
          input.advance(),
        ),
      )
    Some('*') => Err(DanglingQuantifier(pos=off))
    Some('+') => Err(DanglingQuantifier(pos=off))
    Some('?') => Err(DanglingQuantifier(pos=off))
    Some('{') => Err(DanglingQuantifier(pos=off))
    Some('\\') => p_escape(st, input)
    Some(')') => Err(Unexpected(pos=off, expected=["expression"]))
    Some(']') => Err(Unexpected(pos=off, expected=["expression"]))
    Some('}') => Err(Unexpected(pos=off, expected=["expression"]))
    Some('|') => Err(Unexpected(pos=off, expected=["expression"]))
    Some(c) => Ok((make_lit(st, c), input.advance()))
  }
}

///|
/// 字面字符节点：大小写不敏感（`i`）时 lowering 为折叠后的 `Set`，否则 `Lit`。
fn make_lit(st : PState, c : Char) -> Ast {
  if st.flags.ignore_case {
    Set(char_set_of_char(c).case_fold())
  } else {
    Lit(c)
  }
}

///|
/// 转义序列：预定义类 `\d\D\w\W\s\S`、词边界 `\b\B`、文本锚 `\A\z`、反向引用
/// （不支持→报错）与转义字面字符。
fn p_escape(
  st : PState,
  input : @pc.Input,
) -> Result[(Ast, @pc.Input), ParseError] {
  let bs = input.pos.offset
  let after_bs = input.advance() // 消费 '\'
  match after_bs.peek() {
    None =>
      Err(Unexpected(pos=after_bs.pos.offset, expected=["escaped character"]))
    Some('d') => Ok((Set(predef_digit()), after_bs.advance()))
    Some('D') => Ok((Set(predef_non_digit()), after_bs.advance()))
    Some('w') => Ok((Set(predef_word()), after_bs.advance()))
    Some('W') => Ok((Set(predef_non_word()), after_bs.advance()))
    Some('s') => Ok((Set(predef_space()), after_bs.advance()))
    Some('S') => Ok((Set(predef_non_space()), after_bs.advance()))
    Some('b') => Ok((Assert(WordBoundary), after_bs.advance()))
    Some('B') => Ok((Assert(NotWordBoundary), after_bs.advance()))
    Some('A') => Ok((Assert(TextStart), after_bs.advance()))
    Some('z') => Ok((Assert(TextEnd), after_bs.advance()))
    // 反向引用 \1..\9 不支持（需回溯、破坏线性保证）→ 显式报错（R5.6/R10.6）。
    Some(c) =>
      if c >= '1' && c <= '9' {
        Err(Unexpected(pos=bs, expected=["backreference not supported"]))
      } else {
        Ok((make_lit(st, c), after_bs.advance()))
      }
  }
}

///|
/// 分组：捕获 `(...)`、非捕获 `(?:...)`、命名 `(?<name>...)` / `(?P<name>...)`、
/// 前瞻 `(?=...)` / `(?!...)`、内联标志 `(?ims)` / `(?ims:...)`。后瞻
/// `(?<=...)` / `(?<!...)` 不支持（显式报错，R5.6）。
fn p_group(
  st : PState,
  input : @pc.Input,
) -> Result[(Ast, @pc.Input), ParseError] {
  let open = input.pos.offset
  let after_lp = input.advance() // 消费 '('
  match after_lp.peek() {
    Some('?') => {
      let q = after_lp.advance() // 位于 '?' 之后
      match q.peek() {
        Some(':') => p_finish_group(st, q.advance(), open, None, None)
        Some('=') => p_finish_look(st, q.advance(), open, true)
        Some('!') => p_finish_look(st, q.advance(), open, false)
        Some('<') => {
          let lt = q.advance() // 位于 '<' 之后
          match lt.peek() {
            // 后瞻 (?<=...) / (?<!...) 不支持。
            Some('=') =>
              Err(Unexpected(pos=open, expected=["lookbehind not supported"]))
            Some('!') =>
              Err(Unexpected(pos=open, expected=["lookbehind not supported"]))
            _ => p_named_group(st, lt, open)
          }
        }
        Some('P') => {
          let pp = q.advance() // 位于 'P' 之后
          match pp.peek() {
            Some('<') => p_named_group(st, pp.advance(), open)
            _ => Err(Unexpected(pos=open, expected=["(?P<name>"]))
          }
        }
        // 内联标志组 (?ims) / (?ims:...)。
        Some('i') | Some('m') | Some('s') => p_inline_flags(st, q, open)
        _ => Err(Unexpected(pos=open, expected=["group construct"]))
      }
    }
    // 普通捕获组：先序分配编号（DFS 前序）。
    _ => {
      let idx = st.next_group
      st.next_group = st.next_group + 1
      p_finish_group(st, after_lp, open, Some(idx), None)
    }
  }
}

///|
/// 解析命名捕获组 `name>...)`（进入时游标位于 name 首字符）：读名 → 查重 →
/// 先序分配编号并登记 → 解析体 → 闭合。
fn p_named_group(
  st : PState,
  input : @pc.Input,
  open : Int,
) -> Result[(Ast, @pc.Input), ParseError] {
  let (name, after_name) = match read_group_name(input, open) {
    Err(e) => return Err(e)
    Ok(pair) => pair
  }
  // 重复组名 → Unexpected（携带左括号位置），且不构造任何程序 / 自动机（R1.7）。
  match st.names.get(name) {
    Some(_) => return Err(Unexpected(pos=open, expected=["unique group name"]))
    None => ()
  }
  let idx = st.next_group
  st.next_group = st.next_group + 1
  st.names[name] = idx
  p_finish_group(st, after_name, open, Some(idx), Some(name))
}

///|
/// 解析组体并要求闭合 `)`，组装为 `Group(body, index, name)`。
fn p_finish_group(
  st : PState,
  input : @pc.Input,
  open : Int,
  index : Int?,
  name : String?,
) -> Result[(Ast, @pc.Input), ParseError] {
  let (body, rest) = match p_alt(st, input) {
    Err(e) => return Err(e)
    Ok(pair) => pair
  }
  match rest.peek() {
    Some(')') => Ok((Group(body~, index~, name~), rest.advance()))
    _ => Err(Unbalanced(pos=rest.pos.offset, what="("))
  }
}

///|
/// 解析前瞻体并要求闭合 `)`，组装为 `Look(positive, body)`（R5.4/5.5）。
fn p_finish_look(
  st : PState,
  input : @pc.Input,
  open : Int,
  positive : Bool,
) -> Result[(Ast, @pc.Input), ParseError] {
  let (body, rest) = match p_alt(st, input) {
    Err(e) => return Err(e)
    Ok(pair) => pair
  }
  match rest.peek() {
    Some(')') => Ok((Look(positive~, body~), rest.advance()))
    _ => Err(Unbalanced(pos=open, what="("))
  }
}

///|
/// 内联标志组：读取 `i`/`m`/`s` 后，`)` 为 bare（影响后续作用域）、`:` 为 scoped
/// （仅作用于本组体，结束后恢复）。
fn p_inline_flags(
  st : PState,
  input : @pc.Input,
  open : Int,
) -> Result[(Ast, @pc.Input), ParseError] {
  let mut fcur = input
  let mut nf = st.flags
  let mut go = true
  while go {
    match fcur.peek() {
      Some('i') => {
        nf = { ..nf, ignore_case: true }
        fcur = fcur.advance()
      }
      Some('m') => {
        nf = { ..nf, multiline: true }
        fcur = fcur.advance()
      }
      Some('s') => {
        nf = { ..nf, dotall: true }
        fcur = fcur.advance()
      }
      _ => go = false
    }
  }
  match fcur.peek() {
    // bare (?ims)：设置后续作用域标志，产出 Empty。
    Some(')') => {
      st.flags = nf
      Ok((Empty, fcur.advance()))
    }
    // scoped (?ims:...)：局部生效，组结束后恢复。
    Some(':') => {
      let saved = st.flags
      st.flags = nf
      let body_input = fcur.advance()
      let (body, rest) = match p_alt(st, body_input) {
        Err(e) => {
          st.flags = saved
          return Err(e)
        }
        Ok(pair) => pair
      }
      st.flags = saved
      match rest.peek() {
        Some(')') => Ok((Group(body~, index=None, name=None), rest.advance()))
        _ => Err(Unbalanced(pos=open, what="("))
      }
    }
    _ => Err(Unexpected(pos=fcur.pos.offset, expected=["flags, ':' or ')'"]))
  }
}

///|
/// 读取命名组名直至 `>`（进入时游标位于 name 首字符）。名字符为 `[A-Za-z0-9_]`。
fn read_group_name(
  input : @pc.Input,
  open : Int,
) -> Result[(String, @pc.Input), ParseError] {
  let mut cur = input
  let mut name = ""
  let mut go = true
  while go {
    match cur.peek() {
      None => return Err(Unbalanced(pos=open, what="("))
      Some('>') => {
        cur = cur.advance()
        go = false
      }
      Some(c) =>
        if is_name_char(c) {
          name = name + c.to_string()
          cur = cur.advance()
        } else {
          return Err(
            Unexpected(pos=cur.pos.offset, expected=["group name char"]),
          )
        }
    }
  }
  if name.length() == 0 {
    Err(Unexpected(pos=open, expected=["group name"]))
  } else {
    Ok((name, cur))
  }
}

///|
/// 命名组名合法字符：字母 / 数字 / 下划线。
fn is_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// 字符类 `[...]` / `[^...]`，支持内嵌 `\d\w\s`、范围与转义；大小写不敏感时
/// 折叠，否定时取补集。统一规约为 `CharSet` 区间运算（R6.7）。
fn p_class(
  st : PState,
  input : @pc.Input,
) -> Result[(Ast, @pc.Input), ParseError] {
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
  let mut acc : CharSet = { intervals: [] }
  let mut go = true
  while go {
    match cur.peek() {
      None => return Err(Unbalanced(pos=open, what="["))
      Some(']') => {
        cur = cur.advance()
        go = false
      }
      _ => {
        let (tok, after) = match read_class_token(cur, open) {
          Err(e) => return Err(e)
          Ok(pair) => pair
        }
        match tok {
          // 预定义类成员（不参与范围）。
          ClassSet(cs) => {
            acc = acc.union(cs)
            cur = after
          }
          // 单字符成员，可能是范围起点。
          ClassChar(lo) =>
            match after.peek() {
              Some('-') => {
                let dash_next = after.advance()
                match dash_next.peek() {
                  // 紧跟 ']' 的 '-' 视为字面（如 "[a-]"）。
                  Some(']') => {
                    acc = acc.union(char_set_of_char(lo))
                    acc = acc.union(char_set_of_char('-'))
                    cur = dash_next
                  }
                  None => return Err(Unbalanced(pos=open, what="["))
                  _ => {
                    let (tok2, after2) = match
                      read_class_token(dash_next, open) {
                      Err(e) => return Err(e)
                      Ok(pair) => pair
                    }
                    match tok2 {
                      ClassChar(hi) => {
                        acc = acc.union(char_range_set(lo, hi))
                        cur = after2
                      }
                      // 范围端点是预定义类 → '-' 退化为字面。
                      ClassSet(cs) => {
                        acc = acc.union(char_set_of_char(lo))
                        acc = acc.union(char_set_of_char('-'))
                        acc = acc.union(cs)
                        cur = after2
                      }
                    }
                  }
                }
              }
              _ => {
                acc = acc.union(char_set_of_char(lo))
                cur = after
              }
            }
        }
      }
    }
  }
  let folded = if st.flags.ignore_case { acc.case_fold() } else { acc }
  let result = if negated { folded.complement() } else { folded }
  Ok((Set(result), cur))
}

///|
/// 字符类内的一个 token：预定义类集合或单字符。
priv enum ClassTok {
  ClassSet(CharSet)
  ClassChar(Char)
}

///|
/// 读取字符类内一个 token：处理 `\d\w\s` 预定义类与反斜杠转义字面字符。
fn read_class_token(
  input : @pc.Input,
  open : Int,
) -> Result[(ClassTok, @pc.Input), ParseError] {
  match input.peek() {
    None => Err(Unbalanced(pos=open, what="["))
    Some('\\') => {
      let after = input.advance()
      match after.peek() {
        None => Err(Unbalanced(pos=open, what="["))
        Some('d') => Ok((ClassSet(predef_digit()), after.advance()))
        Some('D') => Ok((ClassSet(predef_non_digit()), after.advance()))
        Some('w') => Ok((ClassSet(predef_word()), after.advance()))
        Some('W') => Ok((ClassSet(predef_non_word()), after.advance()))
        Some('s') => Ok((ClassSet(predef_space()), after.advance()))
        Some('S') => Ok((ClassSet(predef_non_space()), after.advance()))
        Some(c) => Ok((ClassChar(c), after.advance()))
      }
    }
    Some(c) => Ok((ClassChar(c), input.advance()))
  }
}

///|
/// 由两个端点字符构造闭区间字符集合（自动校正顺序）。
fn char_range_set(lo : Char, hi : Char) -> CharSet {
  let a = lo.to_int()
  let b = hi.to_int()
  if a <= b {
    { intervals: normalize_intervals([(a, b)]) }
  } else {
    { intervals: normalize_intervals([(b, a)]) }
  }
}
