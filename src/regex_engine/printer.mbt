// printer.mbt —— 语法树 → 正则字符串（`print_regex`），round-trip 配套打印器。
//
// 对应任务 6.1 的打印桩（design.md `print_regex(r : Regex) -> String`）。
// 与 parser.mbt 保持互逆：打印结果应能被 `parse_regex` 重新解析为等价语法树，
// 为任务 6.3「Property 4：Regex 语法树往返」奠定基础。
//
// 互逆要点：
//   * 元字符（`( ) [ ] { } * + ? | ^ $ \`）以字面形式出现时统一反斜杠转义；
//   * 量词只作用于"原子"，故当量词作用对象本身非原子（Concat/Alt/量词节点）
//     时，打印器以分组 `( ... )` 包裹，确保解析时量词绑定到正确范围。

///|
/// 将正则语法树打印为字符串（design.md `print_regex`）。
pub fn print_regex(r : Regex) -> String {
  match r {
    Char(c) => escape_char(c)
    Class(cc) => print_class(cc)
    Star(inner) => print_operand(inner) + "*"
    Plus(inner) => print_operand(inner) + "+"
    Opt(inner) => print_operand(inner) + "?"
    Repeat(inner, m, hi) => print_operand(inner) + print_repeat_suffix(m, hi)
    Concat(parts) => {
      // 以 TextBuilder 顺序物化子节点打印结果，消除循环内字符串 `+` 的
      // O(n²) 拼接（Requirement 1.5 / 1.6）；输出与逐段 `+` 逐字符一致。
      let acc = @infra_text.TextBuilder::new()
      for p in parts {
        acc.push_str(print_regex(p))
      }
      acc.build()
    }
    Alt(branches) => {
      // 分支以 `|` 分隔，经 TextBuilder 物化（同上，消除循环内 `+`）。
      let acc = @infra_text.TextBuilder::new()
      for i, b in branches {
        if i > 0 {
          acc.push_char('|')
        }
        acc.push_str(print_regex(b))
      }
      acc.build()
    }
    Anchor(Start) => "^"
    Anchor(End) => "$"
    Group(inner) => "(" + print_regex(inner) + ")"
  }
}

///|
/// 打印量词作用对象：原子（Char/Class/Anchor/Group）直接打印；其余（Concat/
/// Alt/嵌套量词）以分组包裹，保证量词在重新解析时绑定到同一范围。
fn print_operand(r : Regex) -> String {
  match r {
    Char(_) | Class(_) | Anchor(_) | Group(_) => print_regex(r)
    _ => "(" + print_regex(r) + ")"
  }
}

///|
/// 打印计数量词后缀：`{m}`（上下界相等）/ `{m,}`（无上界）/ `{m,n}`。
fn print_repeat_suffix(m : Int, hi : Int?) -> String {
  match hi {
    None => "{" + m.to_string() + ",}"
    Some(n) =>
      if n == m {
        "{" + m.to_string() + "}"
      } else {
        "{" + m.to_string() + "," + n.to_string() + "}"
      }
  }
}

///|
/// 打印字符类 `[...]` / `[^...]`，对类内特殊字符（`] \ - ^`）做转义。
fn print_class(cc : CharClass) -> String {
  // 以 TextBuilder 物化字符类，消除循环内字符串 `+`（Requirement 1.5 / 1.6）。
  let acc = @infra_text.TextBuilder::new()
  acc.push_char('[')
  if cc.negated {
    acc.push_char('^')
  }
  for item in cc.items {
    match item {
      Single(c) => acc.push_str(escape_class_char(c))
      Range(lo, hi) => {
        acc.push_str(escape_class_char(lo))
        acc.push_char('-')
        acc.push_str(escape_class_char(hi))
      }
    }
  }
  acc.push_char(']')
  acc.build()
}

///|
/// 字面字符转义：元字符前置反斜杠，其余原样输出。
fn escape_char(c : Char) -> String {
  if is_meta(c) {
    "\\" + c.to_string()
  } else {
    c.to_string()
  }
}

///|
/// 字符类内字符转义：仅对类内具有特殊含义的 `] \ - ^` 转义。
fn escape_class_char(c : Char) -> String {
  match c {
    ']' | '\\' | '-' | '^' => "\\" + c.to_string()
    _ => c.to_string()
  }
}

///|
/// 是否为顶层正则元字符（需在字面位置转义）。
fn is_meta(c : Char) -> Bool {
  match c {
    '('
    | ')'
    | '['
    | ']'
    | '{'
    | '}'
    | '*'
    | '+'
    | '?'
    | '|'
    | '^'
    | '$'
    | '\\' => true
    _ => false
  }
}
