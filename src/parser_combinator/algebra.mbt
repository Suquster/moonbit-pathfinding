// algebra.mbt —— L0 代数核心层：functor / monad / applicative 原语。
//
// 对应 tasks.md 任务 1.1，落地 design.md §「组件与接口 → 1. 代数核心层」中
// 锁定的签名级接口。本层把解析器视为「带状态（剩余输入）的计算」，在既有
// 冻结契约（`Parser[T]` / `ParseResult[T]` / `Input` / `Pos`，见 types.mbt）
// 之上以**新增 API** 的形式提供 functor / monad / applicative 地基，严格保持
// 既有 `seq` / `alt` / `many` / `many1` / `optional` 的公开签名与行为不变
// （R1.6 / R14.2）。
//
// 论文出处（design.md §「算法说明与论文对照」）：`pure` / `map` / `bind` 与
// 单子风格组合源自 Hutton & Meijer 1998《Monadic Parser Combinators》。
//
// 实现要点（R1.3 / R1.5）：`map` / `bind` 对 `Fail` 分支必须**原样透传**
// `pos` 与 `expected~` 原值（不重置、不附加、不调用续延函数 `f`），否则会
// 破坏失败传播与单子右单位元律（Property 3 / Property 7）。这些等式（R2）
// 由属性测试承载（任务 1.2~1.5），本文件只负责保证求值语义满足之。

///|
/// `pure`：把一个普通值提升为解析器（applicative / monad 的单位元）。
///
/// 对任意输入恒成功、产出给定 `value`、且**不消费输入**（剩余输入位置与
/// 进入位置逐字段相同）。是 monad 左/右单位元律与 applicative 同态律的基石
/// （R1.1，Property 1）。
pub fn[T] pure(value : T) -> Parser[T] {
  Parser::new(fn(input) { ParseResult::Ok(value, input) })
}

///|
/// `map`（functor）：对解析器产出的值施加纯函数 `f`。
///
/// 当 `p` 在输入上成功并产出 `v` 时，产出 `f(v)` 并保持与 `p` **完全相同的
/// 消费量**（剩余输入位置与 `p` 的剩余输入逐字段一致，R1.2 / Property 2）；
/// 当 `p` 失败时，**原样透传**其失败位置与期望符号集合，且**不调用** `f`
/// （R1.3 / Property 3）。
pub fn[A, B] map(p : Parser[A], f : (A) -> B) -> Parser[B] {
  Parser::new(fn(input) {
    match p.parse(input) {
      Ok(v, rest) => ParseResult::Ok(f(v), rest)
      Fail(pos, expected~) => ParseResult::Fail(pos, expected~)
    }
  })
}

///|
/// `bind`（monad 序列 / `>>=`）：依赖式串联两个解析器。
///
/// 当 `p` 成功产出 `v` 时，在 `p` 的**剩余输入**上运行由 `f(v)` 返回的解析器
/// （后继解析器可依赖前驱产出值，R1.4 / Property 6）；当 `p` 失败时，原样
/// 透传其失败，且**不调用** `f`（R1.5 / Property 3）。
pub fn[A, B] bind(p : Parser[A], f : (A) -> Parser[B]) -> Parser[B] {
  Parser::new(fn(input) {
    match p.parse(input) {
      Ok(v, rest) => (f(v)).parse(rest)
      Fail(pos, expected~) => ParseResult::Fail(pos, expected~)
    }
  })
}

///|
/// `ap`（applicative apply / `<*>`）：先解析出一个函数，再解析出其实参并应用。
///
/// 由 `bind` / `map` 派生：`ap(pf, pa) = bind(pf, fn(f) { map(pa, f) })`——
/// 先运行 `pf` 得到函数 `f`，再在剩余输入上运行 `pa` 得到 `a`，产出 `f(a)`。
/// 供 applicative 恒等律 `ap(pure(id), v) ≡ v` 与同态律
/// `ap(pure(f), pure(x)) ≡ pure(f(x))` 校验及点风格（point-free）组合使用。
pub fn[A, B] ap(pf : Parser[(A) -> B], pa : Parser[A]) -> Parser[B] {
  bind(pf, fn(f) { map(pa, f) })
}

///|
/// `pfail`：恒失败且**不消费输入**的解析器（alternative 的单位元 / 零元）。
///
/// 对任意输入返回 `Fail(input.pos, expected~)`，失败位置取当前游标位置、
/// 期望符号取给定 `expected`。它是 `alt` 左单位元律
/// `alt([pfail, p]) ≡ p`（R2.6 / Property 9）的左零元，也用于 fail-fast
/// 场景下显式构造一个携带期望信息的失败分支。
pub fn[T] pfail(expected~ : Array[String]) -> Parser[T] {
  Parser::new(fn(input) { ParseResult::Fail(input.pos, expected~) })
}
