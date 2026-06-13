// derived.mbt —— L0 衍生组合子代数（derived combinators）。
//
// 对应 tasks.md 任务 2.1，落地 design.md §「组件与接口 → 2. 衍生组合子代数」。
// 全部以既有 L0 原语 + `bind` / `map` / `alt` / `many`（algebra.mbt /
// combinators.mbt）组合而成，不触碰任何冻结契约的签名（R14）。
//
// 论文出处（design.md §「算法说明与论文对照」）：`chainl1` / `chainr1` 与单子
// 风格折叠源自 Hutton & Meijer 1998《Monadic Parser Combinators》。

///|
/// `sep_by1(p, sep)`：解析**至少一个** `p`，以 `sep` 分隔，收集为产出数组。
///
/// 算法：先解析首个 `p`，再 `many(seq(sep, p))` 收集后续 `(分隔符, 元素)` 对，
/// 取其中的元素拼到结果数组。无任何 `p` 时在 `p` 起始位置失败并报告 `p` 的
/// 期望符号（R3.2）。
pub fn[T, S] sep_by1(p : Parser[T], sep : Parser[S]) -> Parser[Array[T]] {
  bind(p, fn(first) {
    map(many(seq(sep, p)), fn(rest) {
      let acc : Array[T] = [first]
      for pair in rest {
        acc.push(pair.1)
      }
      acc
    })
  })
}

///|
/// `sep_by(p, sep)`：解析**零个或多个** `p`，以 `sep` 分隔，收集为产出数组。
///
/// 零个时产出空数组且不消费输入（R3.1）。实现为 `sep_by1` 与「恒成功产出空
/// 数组」的择一：`alt([sep_by1(p, sep), pure([])])`。
pub fn[T, S] sep_by(p : Parser[T], sep : Parser[S]) -> Parser[Array[T]] {
  let empty : Array[T] = []
  alt([sep_by1(p, sep), pure(empty)])
}

///|
/// `between(open, body, close)`：先消费 `open`、再运行 `body`、最后消费 `close`，
/// **仅保留** `body` 的产出值并消费三者覆盖的全部输入（R3.3）。
pub fn[O, T, C] between(
  open : Parser[O],
  body : Parser[T],
  close : Parser[C],
) -> Parser[T] {
  bind(open, fn(_o) { bind(body, fn(b) { map(close, fn(_c) { b }) }) })
}

///|
/// `chainl1(operand, op)`：以**左结合**方式用二元运算符 `op` 折叠操作数序列。
///
/// 文法 `operand (op operand)*`：先解析首个操作数 `x`，再 `many(seq(op, operand))`
/// 收集 `(运算符函数, 操作数)` 序列，按 `acc := f(acc, y)` **自左向右**折叠为
/// 单一产出值（R3.4，消除手写左递归，Hutton & Meijer 1998 §chainl）。
pub fn[T] chainl1(operand : Parser[T], op : Parser[(T, T) -> T]) -> Parser[T] {
  bind(operand, fn(first) {
    map(many(seq(op, operand)), fn(rest) {
      let mut acc = first
      for pair in rest {
        let f = pair.0
        let y = pair.1
        acc = f(acc, y)
      }
      acc
    })
  })
}

///|
/// `chainr1(operand, op)`：以**右结合**方式用二元运算符 `op` 折叠操作数序列。
///
/// 文法 `operand (op operand)*`：先收集首个操作数与全部 `(运算符函数, 操作数)`
/// 序列，再**自右向左**折叠（R3.5）。等价于递归式
/// `x >>= λ. (op >>= λf. chainr1 >>= λy. pure(f(x,y))) <|> pure(x)`，此处以
/// 显式右折叠实现以避免深递归。
pub fn[T] chainr1(operand : Parser[T], op : Parser[(T, T) -> T]) -> Parser[T] {
  bind(operand, fn(first) {
    map(many(seq(op, operand)), fn(rest) {
      if rest.length() == 0 {
        first
      } else {
        // 操作数序列：[first, rest[0].1, rest[1].1, ...]
        // 运算符序列：[rest[0].0, rest[1].0, ...]
        // 右结合折叠：从最右一对开始向左累积。
        let operands : Array[T] = [first]
        let ops : Array[(T, T) -> T] = []
        for pair in rest {
          ops.push(pair.0)
          operands.push(pair.1)
        }
        let mut acc = operands[operands.length() - 1]
        let mut i = ops.length() - 1
        while i >= 0 {
          let f = ops[i]
          acc = f(operands[i], acc)
          i = i - 1
        }
        acc
      }
    })
  })
}

///|
/// `chainl(operand, op, default)`：允许**空**操作数序列的左结合折叠。
///
/// 零操作数时产出 `default` 且不消费输入（R3.6）；否则等价于 `chainl1`。
pub fn[T] chainl(
  operand : Parser[T],
  op : Parser[(T, T) -> T],
  default : T,
) -> Parser[T] {
  alt([chainl1(operand, op), pure(default)])
}

///|
/// `chainr(operand, op, default)`：允许**空**操作数序列的右结合折叠。
///
/// 零操作数时产出 `default` 且不消费输入（R3.6）；否则等价于 `chainr1`。
pub fn[T] chainr(
  operand : Parser[T],
  op : Parser[(T, T) -> T],
  default : T,
) -> Parser[T] {
  alt([chainr1(operand, op), pure(default)])
}

///|
/// `lazy_parser(thunk)`：把解析器的**构造**推迟到首次 `run` 时求值。
///
/// 用于打破递归文法的构造期循环依赖（R3.7）：`thunk` 在每次 `run` 时才被调用，
/// 因此对自身的递归引用在构造期不会展开为无限结构（与 `Parser[T]` 是函数包装
/// 这一既有设计契合）。
///
/// 命名说明：design.md 记为 `lazy`，但 `lazy` 是 MoonBit 的保留字，故落地为
/// `lazy_parser`（语义不变）。
pub fn[T] lazy_parser(thunk : () -> Parser[T]) -> Parser[T] {
  Parser::new(fn(input) { thunk().parse(input) })
}
