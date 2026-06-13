// arith.mbt —— L2 旗舰示例：算术表达式求值器（R11.5, R11.6, R11.8）。
//
// 对应 tasks.md 任务 13.1，展示运算符优先级与左/右结合：
//   expr   := term  (('+'|'-') term)*      左结合，chainl1
//   term   := factor(('*'|'/') factor)*    左结合，chainl1
//   factor := base  ('^' base)*            右结合，chainr1
//   base   := number | '(' expr ')'
//
// 论文映射：`chainl1` / `chainr1` 折叠源自 Hutton & Meijer 1998。R9.5 的左递归
// 与 chainl1 差分一致性由 left_recursion_prop_test.mbt 的 Property 25 承载。

///|
/// 算术表达式 AST。`derive(Eq)` 供结构比较。
pub(all) enum Expr {
  Num(Double)
  Add(Expr, Expr)
  Sub(Expr, Expr)
  Mul(Expr, Expr)
  Div(Expr, Expr)
  Pow(Expr, Expr)
} derive(Eq)

///|
/// 跳过零个或多个空白（空格 / 制表）。
fn arith_ws() -> Parser[Unit] {
  map(many(satisfy(fn(c) { c == ' ' || c == '\t' }, label="空白")), fn(_u) { () })
}

///|
/// 数字（非负，可选小数）→ `Num(Double)`（已跳过前导空白）。
fn arith_number() -> Parser[Expr] {
  bind(arith_ws(), fn(_u) {
    bind(many1(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")), fn(intd) {
      bind(
        optional(
          seq(
            pchar('.'),
            many1(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")),
          ),
        ),
        fn(fracopt) {
          let mut v = 0.0
          for c in intd {
            v = v * 10.0 + (c.to_int() - '0'.to_int()).to_double()
          }
          match fracopt {
            Some((_dot, fd)) => {
              let mut scale = 0.1
              for c in fd {
                v = v + (c.to_int() - '0'.to_int()).to_double() * scale
                scale = scale / 10.0
              }
            }
            None => ()
          }
          pure(Num(v))
        },
      )
    })
  })
}

///|
/// 先跳过前导空白再匹配字符 `c`。
fn arith_lex_char(c : Char) -> Parser[Char] {
  bind(arith_ws(), fn(_u) { pchar(c) })
}

///|
/// base := number | '(' expr ')'。
fn arith_base() -> Parser[Expr] {
  alt([
    arith_number(),
    between(arith_lex_char('('), expr_parser(), arith_lex_char(')')),
  ])
}

///|
/// `^` 运算符（右结合）→ 二元构造函数。
fn arith_pow_op() -> Parser[(Expr, Expr) -> Expr] {
  map(arith_lex_char('^'), fn(_c) { fn(a : Expr, b : Expr) -> Expr { Pow(a, b) } })
}

///|
/// `*` / `/` 运算符（左结合）→ 二元构造函数。
fn arith_muldiv_op() -> Parser[(Expr, Expr) -> Expr] {
  bind(arith_ws(), fn(_u) {
    alt([
      map(pchar('*'), fn(_c) { fn(a : Expr, b : Expr) -> Expr { Mul(a, b) } }),
      map(pchar('/'), fn(_c) { fn(a : Expr, b : Expr) -> Expr { Div(a, b) } }),
    ])
  })
}

///|
/// `+` / `-` 运算符（左结合）→ 二元构造函数。
fn arith_addsub_op() -> Parser[(Expr, Expr) -> Expr] {
  bind(arith_ws(), fn(_u) {
    alt([
      map(pchar('+'), fn(_c) { fn(a : Expr, b : Expr) -> Expr { Add(a, b) } }),
      map(pchar('-'), fn(_c) { fn(a : Expr, b : Expr) -> Expr { Sub(a, b) } }),
    ])
  })
}

///|
/// factor := base ('^' base)*（右结合幂运算，chainr1）。
fn arith_factor() -> Parser[Expr] {
  chainr1(arith_base(), arith_pow_op())
}

///|
/// term := factor (('*'|'/') factor)*（左结合，chainl1）。
fn arith_term() -> Parser[Expr] {
  chainl1(arith_factor(), arith_muldiv_op())
}

///|
/// expr := term (('+'|'-') term)*（左结合，chainl1）；经 `lazy_parser` 打破
/// `base := '(' expr ')'` 的递归构造期循环。
pub fn expr_parser() -> Parser[Expr] {
  lazy_parser(fn() { chainl1(arith_term(), arith_addsub_op()) })
}

///|
/// 整数次幂（支持负整数指数）；非整数指数不在生成器范围内，回退为底数。
fn arith_pow_eval(base : Double, exp : Double) -> Double {
  let e = exp.to_int()
  if e.to_double() == exp && e >= 0 {
    let mut r = 1.0
    let mut i = 0
    while i < e {
      r = r * base
      i = i + 1
    }
    r
  } else if e.to_double() == exp {
    let mut r = 1.0
    let mut i = 0
    while i < -e {
      r = r * base
      i = i + 1
    }
    1.0 / r
  } else {
    base
  }
}

///|
/// 按 AST 直接求值（参照求值器，R11.8）。
pub fn eval_expr(e : Expr) -> Double {
  match e {
    Num(d) => d
    Add(a, b) => eval_expr(a) + eval_expr(b)
    Sub(a, b) => eval_expr(a) - eval_expr(b)
    Mul(a, b) => eval_expr(a) * eval_expr(b)
    Div(a, b) => eval_expr(a) / eval_expr(b)
    Pow(a, b) => arith_pow_eval(eval_expr(a), eval_expr(b))
  }
}

///|
/// 打印数值：整数值打印为整数，否则用 Double 默认表示。
fn arith_print_num(d : Double) -> String {
  let i = d.to_int()
  if i.to_double() == d {
    "\{i}"
  } else {
    "\{d}"
  }
}

///|
/// 完全括号化打印器：每个二元节点以一对括号唯一界定，使打印形式与解析互为
/// 双射（解析可无歧义恢复同一结构），从而支撑求值一致性（R11.8）。
pub fn print_expr(e : Expr) -> String {
  match e {
    Num(d) => arith_print_num(d)
    Add(a, b) => "(" + print_expr(a) + "+" + print_expr(b) + ")"
    Sub(a, b) => "(" + print_expr(a) + "-" + print_expr(b) + ")"
    Mul(a, b) => "(" + print_expr(a) + "*" + print_expr(b) + ")"
    Div(a, b) => "(" + print_expr(a) + "/" + print_expr(b) + ")"
    Pow(a, b) => "(" + print_expr(a) + "^" + print_expr(b) + ")"
  }
}

///|
/// 顶层入口：解析中缀算术表达式并按优先级 / 结合性求值（R11.5）。
///
/// 成功返回 `Ok(数值)`；语法错误或尾随未消费输入返回 `@core.PathError`。
pub fn parse_and_eval(src : String) -> Result[Double, @core.PathError] {
  let full = bind(expr_parser(), fn(e) { map(arith_ws(), fn(_u) { e }) })
  match full.parse_string(src) {
    Ok(e, rest) =>
      if rest.is_eof() {
        Ok(eval_expr(e))
      } else {
        Err(
          @core.PathError::InvalidInput(
            "算术表达式存在尾随未消费输入于 \{rest.pos}（offset \{rest.pos.offset}）",
          ),
        )
      }
    Fail(_, ..) as f =>
      match f.to_path_error() {
        Some(e) => Err(e)
        None => Err(@core.PathError::InvalidInput("算术表达式解析失败"))
      }
  }
}
