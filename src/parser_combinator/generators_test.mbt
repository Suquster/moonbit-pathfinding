// generators_test.mbt —— L0 共享属性测试生成器（task 1.6）。
//
// 落地 design.md §「测试策略 → 生成器策略」中锁定的 `gen_parser` / `gen_input`：
// 在一个**有限组合子字母表**（`pchar` / `satisfy` / `pure` / `pfail` / `map` /
// `bind` / `alt` / `seq` / `many`）上按受限深度采样，产出 `Parser[Int]`；配套
// `gen_input` 在同一字符集上采样输入，使生成的解析器与输入「有意义地」交互，
// 从而真正触发代数定律的两侧分支（成功 / 失败）。全部复用 @infra_pbt.Rng
// （xorshift64，种子驱动、三后端逐位一致、可重放）。
//
// 本文件定义的生成器与比较辅助在本包的黑盒测试集内共享，供 algebra /
// derived / error_model 等属性测试复用（_Requirements: 2.1, 14.4_）。

///|
/// 解析器 / 输入共用的字符字母表：刻意短小且与 `pchar` 叶子一致，使 `a/b/c`
/// 高频出现，从而充分触发匹配成功与失败两条路径。
let pc_alphabet : Array[Char] = ['a', 'b', 'c']

///|
/// 在给定剩余深度下采样一个 `Parser[Int]`。
///
/// 叶子（深度耗尽或 1/3 概率提前收敛）：`pure`（恒成功）、`pfail`（恒失败，
/// 期望非空以满足 R5.1）、或把 `pchar(c)` 映射为其码位的 `map`。
/// 内节点：`map` / `bind` / `alt` / `seq`（折叠为 Int）/ `many`（取长度），
/// 覆盖核心组合子字母表。深度上限保证树规模有界。
fn gen_parser_int_at(rng : @infra_pbt.Rng, depth : Int) -> Parser[Int] {
  if depth <= 0 || rng.next_below(3) == 0 {
    match rng.next_below(3) {
      0 => pure(rng.next_range(0, 9))
      1 => pfail(expected=["fail"])
      _ => {
        let c = pc_alphabet[rng.next_below(pc_alphabet.length())]
        map(pchar(c), fn(ch) { ch.to_int() })
      }
    }
  } else {
    match rng.next_below(5) {
      0 => map(gen_parser_int_at(rng, depth - 1), fn(n) { n + 1 })
      1 => {
        let q = gen_parser_int_at(rng, depth - 1)
        bind(gen_parser_int_at(rng, depth - 1), fn(_n) { q })
      }
      2 =>
        alt([
          gen_parser_int_at(rng, depth - 1),
          gen_parser_int_at(rng, depth - 1),
        ])
      3 =>
        map(
          seq(
            gen_parser_int_at(rng, depth - 1),
            gen_parser_int_at(rng, depth - 1),
          ),
          fn(pair) { pair.0 + pair.1 },
        )
      _ => map(many(gen_parser_int_at(rng, depth - 1)), fn(arr) { arr.length() })
    }
  }
}

///|
/// `gen_parser`：受限深度（3）的 `Parser[Int]` 生成器。
fn gen_parser() -> @infra_pbt.Gen[Parser[Int]] {
  @infra_pbt.Gen::new(fn(rng) { gen_parser_int_at(rng, 3) })
}

///|
/// 在 `pc_alphabet` 上采样一个长度 0~6 的随机输入字符串。
fn gen_input_str(rng : @infra_pbt.Rng) -> String {
  let len = rng.next_range(0, 6)
  let mut s = ""
  let mut i = 0
  while i < len {
    let c = pc_alphabet[rng.next_below(pc_alphabet.length())]
    s = s + "\{c}"
    i = i + 1
  }
  s
}

///|
/// `gen_input`：与解析器共用字符集的输入字符串生成器。
fn gen_input() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) { gen_input_str(rng) })
}

///|
/// 采样一个确定性纯函数 `Int -> Int`（供 functor / monad 定律使用）。
fn gen_fun_int(rng : @infra_pbt.Rng) -> (Int) -> Int {
  match rng.next_below(4) {
    0 => fn(n) { n + 1 }
    1 => fn(n) { n * 2 }
    2 => fn(n) { n - 3 }
    _ => fn(n) { n % 7 }
  }
}

///|
/// 采样一个确定性函数 `Int -> Parser[Int]`（供 monad 定律使用）。
///
/// 三种形态分别演示：依赖产出值的 `pure`、忽略产出值消费一个字符、以及依产出
/// 值奇偶性在成功 / 失败之间分流——从而充分触发 `bind` 的成功与失败路径。
fn gen_fun_parser(rng : @infra_pbt.Rng) -> (Int) -> Parser[Int] {
  match rng.next_below(3) {
    0 => fn(n) { pure(n + 1) }
    1 => fn(_n) { map(pchar('a'), fn(c) { c.to_int() }) }
    _ => fn(n) { if n % 2 == 0 { pure(n) } else { pfail(expected=["odd"]) } }
  }
}

///|
/// 解析结果的逐字段比较（field-wise equality）。
///
/// 成功：产出值相等且剩余输入偏移相等；失败：失败位置偏移相等且期望集合
/// 逐元素相等。用于校验代数定律「两侧产生逐字段一致的解析结果」。
fn presult_eq(a : ParseResult[Int], b : ParseResult[Int]) -> Bool {
  match (a, b) {
    (Ok(v1, r1), Ok(v2, r2)) => v1 == v2 && r1.pos.offset == r2.pos.offset
    (Fail(p1, expected=e1), Fail(p2, expected=e2)) =>
      p1.offset == p2.offset && e1 == e2
    _ => false
  }
}


///|
/// 在给定剩余深度下采样一个引擎层富解析器 `Grammar[Int]`。
///
/// 覆盖 `lift` / `memoize` / `map` / `bind` / `choice` / `commit` 等运行期组合，
/// 供 packrat 差分一致性（Property 23）与缓存隔离（Property 24）的差分校验使用。
fn gen_grammar_at(rng : @infra_pbt.Rng, depth : Int) -> Grammar[Int] {
  if depth <= 0 || rng.next_below(3) == 0 {
    lift(gen_parser_int_at(rng, 1))
  } else {
    match rng.next_below(5) {
      0 => memoize(gen_grammar_at(rng, depth - 1))
      1 => gen_grammar_at(rng, depth - 1).map(fn(n) { n + 1 })
      2 =>
        choice([gen_grammar_at(rng, depth - 1), gen_grammar_at(rng, depth - 1)])
      3 => {
        let q = gen_grammar_at(rng, depth - 1)
        gen_grammar_at(rng, depth - 1).bind(fn(_n) { q })
      }
      _ => commit(gen_grammar_at(rng, depth - 1))
    }
  }
}

///|
/// `gen_grammar`：受限深度（3）的 `Grammar[Int]` 生成器。
fn gen_grammar() -> @infra_pbt.Gen[Grammar[Int]] {
  @infra_pbt.Gen::new(fn(rng) { gen_grammar_at(rng, 3) })
}

///|
/// 解析结果逐字段比较（与 presult_eq 同语义，供 Grammar 层 ParseResult 复用）。
fn gresult_eq(a : ParseResult[Int], b : ParseResult[Int]) -> Bool {
  presult_eq(a, b)
}
