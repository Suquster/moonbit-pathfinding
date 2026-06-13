// ast.mbt —— 富语法树 `Ast` / 零宽断言种类 `AssertKind`、子集提升桥
// `Ast::of_regex` 与调试打印 `print_ast`（旗舰深化）。
//
// 对应 design.md §4.1（R1/R3/R5/R6/R12.6）。本文件为**新增**，不改既有
// `Regex`（types.mbt）。既有 `Regex` 不足以表达捕获编号、惰性标志、零宽断言
// 与已 lowering 的字符集合，故引入富语法树 `Ast`：预定义类 `\d\w\s` 与点号
// `.` 在解析期即 lowering 为 `CharSet`（R6.7「统一规约为 CharSet 区间运算」），
// `Ast` 不保留符号节点。
//
// paper-to-code：节点形态对应 Thompson 1968 的正则构造单元（字面 / 串接 /
// 择一 / 闭包 / 分组），并扩展捕获寄存器（`Group.index`）、量词贪婪标志
// （`Repeat.greedy`，Russ Cox Pike VM）与零宽断言（`Assert`/`Look`）。

///|
/// 零宽位置断言种类（zero-width assertion kind）。
///
///   * `TextStart` / `TextEnd` —— 整串首 / 尾（非多行下的 `^` / `$`，或 `\A` / `\z`）；
///   * `LineStart` / `LineEnd` —— 行首 / 行尾（多行下的 `^` / `$`）；
///   * `WordBoundary` / `NotWordBoundary` —— `\b` / `\B`。
pub(all) enum AssertKind {
  TextStart
  TextEnd
  LineStart
  LineEnd
  WordBoundary
  NotWordBoundary
} derive(Eq)

///|
/// 富语法树（rich AST）：旗舰执行流水线 `pattern → Ast → Program` 的中间表示。
///
///   * `Empty` —— 空表达式；
///   * `Lit(c)` —— 字面字符（大小写折叠在编译期按 `i` 标志处理）；
///   * `Set(cs)` —— 字符集合（`[...]`、`\d\w\s`、`.` 等统一 lowering 结果）；
///   * `Concat` / `Alt` —— 串接 / 择一；
///   * `Repeat{node,min,max,greedy}` —— `*`/`+`/`?`/`{m,n}` 及其惰性变体；
///   * `Group{body,index,name}` —— `index=None` 即非捕获组 `(?:...)`；
///   * `Assert(kind)` —— 零宽位置断言；
///   * `Look{positive,body}` —— 正 / 负前瞻 `(?=...)` / `(?!...)`。
pub(all) enum Ast {
  Empty
  Lit(Char)
  Set(CharSet)
  Concat(Array[Ast])
  Alt(Array[Ast])
  Repeat(node~ : Ast, min~ : Int, max~ : Int?, greedy~ : Bool)
  Group(body~ : Ast, index~ : Int?, name~ : String?)
  Assert(AssertKind)
  Look(positive~ : Bool, body~ : Ast)
} derive(Eq)

///|
/// 子集提升桥：把既有 `Regex` 语法树提升为等价 `Ast`（保持语义，R12.6）。
///
/// 用于多引擎差分一致性——把生成器产出的受支持子集正则喂入 Pike VM。映射：
/// 既有 `Group` → 非捕获 `Group(index=None)`；`Star/Plus/Opt/Repeat` →
/// `Repeat(greedy=true)`；`Anchor(Start/End)` → `Assert(TextStart/TextEnd)`
/// （非多行默认）；`Class` → `Set(char_set_of_class(..))`。
pub fn Ast::of_regex(r : Regex) -> Ast {
  match r {
    Char(c) => Lit(c)
    Class(cc) => Set(char_set_of_class(cc))
    Star(inner) =>
      Repeat(node=Ast::of_regex(inner), min=0, max=None, greedy=true)
    Plus(inner) =>
      Repeat(node=Ast::of_regex(inner), min=1, max=None, greedy=true)
    Opt(inner) =>
      Repeat(node=Ast::of_regex(inner), min=0, max=Some(1), greedy=true)
    Repeat(inner, m, hi) =>
      Repeat(node=Ast::of_regex(inner), min=m, max=hi, greedy=true)
    Concat(parts) => {
      let out : Array[Ast] = []
      for p in parts {
        out.push(Ast::of_regex(p))
      }
      Concat(out)
    }
    Alt(branches) => {
      let out : Array[Ast] = []
      for b in branches {
        out.push(Ast::of_regex(b))
      }
      Alt(out)
    }
    Anchor(Start) => Assert(TextStart)
    Anchor(End) => Assert(TextEnd)
    Group(inner) => Group(body=Ast::of_regex(inner), index=None, name=None)
  }
}

///|
/// 调试打印：把富语法树打印为人类可读、尽量可重新解析的文本（供调试与扩展
/// 往返）。命名 / 非捕获组、惰性量词与断言均可读地呈现。
pub fn print_ast(a : Ast) -> String {
  match a {
    Empty => ""
    Lit(c) => escape_char(c)
    Set(cs) => print_ast_set(cs)
    Concat(parts) => {
      let mut acc = ""
      for p in parts {
        acc = acc + print_ast(p)
      }
      acc
    }
    Alt(branches) => {
      let mut acc = ""
      for i, b in branches {
        if i > 0 {
          acc = acc + "|"
        }
        acc = acc + print_ast(b)
      }
      acc
    }
    Repeat(node~, min~, max~, greedy~) => {
      let body = print_ast_operand(node)
      let suffix = print_ast_quant(min, max)
      body + suffix + (if greedy { "" } else { "?" })
    }
    Group(body~, index~, name~) =>
      match name {
        Some(nm) => "(?<" + nm + ">" + print_ast(body) + ")"
        None =>
          match index {
            Some(_) => "(" + print_ast(body) + ")"
            None => "(?:" + print_ast(body) + ")"
          }
      }
    Assert(kind) =>
      match kind {
        TextStart => "\\A"
        TextEnd => "\\z"
        LineStart => "^"
        LineEnd => "$"
        WordBoundary => "\\b"
        NotWordBoundary => "\\B"
      }
    Look(positive~, body~) =>
      (if positive { "(?=" } else { "(?!" }) + print_ast(body) + ")"
  }
}

///|
/// 打印量词作用对象：原子（Lit/Set/Group/Assert/Look）直接打印，其余
/// （Concat/Alt/Repeat/Empty）以非捕获组包裹，保证重新解析时绑定范围一致。
fn print_ast_operand(a : Ast) -> String {
  match a {
    Lit(_) | Set(_) | Group(..) | Assert(_) | Look(..) => print_ast(a)
    _ => "(?:" + print_ast(a) + ")"
  }
}

///|
/// 打印量词后缀：`*`（0,None）/ `+`（1,None）/ `?`（0,Some 1）/ `{m}` /
/// `{m,}` / `{m,n}`。
fn print_ast_quant(min : Int, max : Int?) -> String {
  match (min, max) {
    (0, None) => "*"
    (1, None) => "+"
    (0, Some(1)) => "?"
    (m, None) => "{" + m.to_string() + ",}"
    (m, Some(n)) =>
      if m == n {
        "{" + m.to_string() + "}"
      } else {
        "{" + m.to_string() + "," + n.to_string() + "}"
      }
  }
}

///|
/// 打印字符集合（调试形态）：单点集合打印为字面字符；否则以 `[...]` 列出
/// 区间。为可读性，对覆盖到高码点的大集合以 `.` 占位。
fn print_ast_set(cs : CharSet) -> String {
  if cs.intervals.length() == 1 {
    let (lo, hi) = cs.intervals[0]
    if lo == hi && lo >= 0 && lo < 0x110000 {
      return escape_char(lo.unsafe_to_char())
    }
  }
  let mut s = "["
  for iv in cs.intervals {
    let (lo, hi) = iv
    if hi >= 0x10000 {
      // 覆盖到高码点的大区间，以省略号占位（调试可读性）。
      s = s + "\u{2026}"
    } else if lo == hi {
      s = s + lo.unsafe_to_char().to_string()
    } else {
      s = s +
        lo.unsafe_to_char().to_string() +
        "-" +
        hi.unsafe_to_char().to_string()
    }
  }
  s + "]"
}
