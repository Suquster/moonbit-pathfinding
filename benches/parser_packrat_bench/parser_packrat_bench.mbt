// benches/parser_packrat_bench — T4.3 packrat vs 朴素复杂度趋势（回溯密集文法）。
//
// 文法（歧义括号，Ford 2002 packrat 论文的经典触发形态）：
//   S(0) ::= '1'
//   S(d) ::= '(' S(d-1) ')'   —— 分支 1
//          | '(' S(d-1) ']'   —— 分支 2
//          | '1'
//
// 输入 `"((( … 1 ]]] …"`（全部使用分支 2 的闭括号）迫使朴素模式在每层先把
// 分支 1 的 `S(d-1)` **完整解析到底**、于 `')'` 处失败回溯，再在分支 2 **原位
// 重解析** `S(d-1)`——重解析次数随深度呈 2^d 指数增长；packrat 对每个
// `S(d)`×位置记忆化后每位置至多算一次，总量 O(d) 线性。
//
// 复杂度趋势由**确定性求值计数**（原子命中计数器）guard 锁定（与计时无关、
// 跨机器稳定），计时对比另以 `moon bench` 固化到 benches/results/ 工件。

///|
/// 构造使用分支 2 闭括号的深度 d 输入：`(((1]]]`。
fn make_bracket_input(d : Int) -> String {
  let mut open = ""
  let mut close = ""
  let mut i = 0
  while i < d {
    open = open + "("
    close = close + "]"
    i = i + 1
  }
  open + "1" + close
}

///|
/// 单字符富解析器。
fn ch(c : Char) -> @pc.Grammar[Char] {
  @pc.lift(@pc.satisfy(fn(x) { x == c }, label=c.to_string()))
}

///|
/// 构造深度 `depth` 的歧义括号文法；`counter` 统计原子 '1' 的实际求值次数
/// （memo 命中不计数），是复杂度趋势的确定性观测点。
fn bracket_grammar(depth : Int, counter : Array[Int]) -> @pc.Grammar[Int] {
  let atom : @pc.Grammar[Int] = @pc.memoize(
    ch('1').map(fn(_c) {
      counter[0] = counter[0] + 1
      1
    }),
  )
  let mut s = atom
  for _i in 0..<depth {
    let inner = s
    let branch1 = ch('(').bind(fn(_o) {
      inner.bind(fn(v) { ch(')').map(fn(_c) { v + 1 }) })
    })
    let branch2 = ch('(').bind(fn(_o) {
      inner.bind(fn(v) { ch(']').map(fn(_c) { v + 1 }) })
    })
    s = @pc.memoize(@pc.choice([branch1, branch2, atom]))
  }
  s
}

///|
/// Guard（T4.3 复杂度趋势，确定性）：朴素模式原子求值次数随深度指数增长
/// （≥ 2^d），packrat 每位置至多一次（≤ d+1，线性）；两种入口解析结果一致。
test "guard: packrat is linear while naive is exponential on ambiguous brackets" {
  let depths = [4, 8, 12]
  for d in depths {
    let input = make_bracket_input(d)
    // 朴素：指数级原子重求值。
    let c_naive : Array[Int] = [0]
    let g_naive = bracket_grammar(d, c_naive)
    let r_naive = g_naive.run_naive_string(input)
    assert_true(r_naive.is_ok())
    // 2^d 次分支组合各到达一次原子（保守下界取 2^(d-1)）。
    let mut lower = 1
    for _i in 0..<(d - 1) {
      lower = lower * 2
    }
    assert_true(c_naive[0] >= lower)
    // packrat：线性——每位置至多一次。
    let c_pack : Array[Int] = [0]
    let g_pack = bracket_grammar(d, c_pack)
    let r_pack = g_pack.run_packrat_string(input)
    assert_true(r_pack.is_ok())
    assert_true(c_pack[0] <= d + 1)
    // 两入口产出一致（深度值）。
    match (r_naive, r_pack) {
      (Ok(a, _), Ok(b, _)) => assert_eq(a, b)
      _ => assert_true(false)
    }
  }
}

///|
/// Native benchmark：回溯密集文法上 packrat vs 朴素的计时趋势。
test "bench: packrat vs naive on backtracking-heavy grammar" (b : @bench.T) {
  let depths = [8, 12, 16]
  for d in depths {
    let input = make_bracket_input(d)
    let counter : Array[Int] = [0]
    let g = bracket_grammar(d, counter)
    b.bench(name="brackets_packrat_\{d}", fn() {
      b.keep(g.run_packrat_string(input))
    })
    b.bench(name="brackets_naive_\{d}", fn() {
      b.keep(g.run_naive_string(input))
    })
  }
}
