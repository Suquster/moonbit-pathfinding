// benches/parser_arith_bench — 算术表达式求值基准（packrat vs 朴素，递增规模）。
//
// 工作负载（R12.1）：解析逐渐增长的中缀算术表达式（长加法链 + 深嵌套括号），
// 分别以 `run_packrat` 与 `run_naive` 计时（R12.3）。smoke 测试保证工作负载在
// 两种入口均可正确解析。
//
// _Requirements: 12.1, 12.2, 12.3, 12.5_

///|
/// 构造长加法链 `1+1+...+1`（n 个操作数）。
fn make_sum_chain(n : Int) -> String {
  let mut s = "1"
  let mut i = 1
  while i < n {
    s = s + "+1"
    i = i + 1
  }
  s
}

///|
/// 构造深嵌套括号表达式 `((((1))))`（深度 d）。
fn make_nested_parens(d : Int) -> String {
  let mut open = ""
  let mut close = ""
  let mut i = 0
  while i < d {
    open = open + "("
    close = close + ")"
    i = i + 1
  }
  open + "1" + close
}

///|
/// 算术表达式的引擎版富解析器（lift L0 表达式解析器）。
fn arith_grammar() -> @pc.Grammar[@pc.Expr] {
  @pc.lift(@pc.expr_parser())
}

///|
/// Smoke guard：基准工作负载在 packrat / 朴素入口均能正确解析。
test "smoke: parser_arith bench workload parses under both run modes" {
  let g = arith_grammar()
  let chain = make_sum_chain(32)
  let nested = make_nested_parens(16)
  assert_true(g.run_packrat_string(chain).is_ok())
  assert_true(g.run_naive_string(chain).is_ok())
  assert_true(g.run_packrat_string(nested).is_ok())
  assert_true(g.run_naive_string(nested).is_ok())
  // 端到端求值正确性抽查。
  assert_true(@pc.parse_and_eval(make_sum_chain(10)) == Ok(10.0))
}

///|
/// Native benchmark：packrat vs 朴素在递增规模下的计时对比。
test "bench: parser_arith packrat vs naive over increasing sizes" (b : @bench.T) {
  let g = arith_grammar()
  let sizes = [16, 64, 256]
  for n in sizes {
    let input = make_sum_chain(n)
    b.bench(name="arith_sum_packrat_\{n}", fn() {
      b.keep(g.run_packrat_string(input))
    })
    b.bench(name="arith_sum_naive_\{n}", fn() {
      b.keep(g.run_naive_string(input))
    })
  }
  let depths = [8, 16, 32]
  for d in depths {
    let input = make_nested_parens(d)
    b.bench(name="arith_parens_packrat_\{d}", fn() {
      b.keep(g.run_packrat_string(input))
    })
    b.bench(name="arith_parens_naive_\{d}", fn() {
      b.keep(g.run_naive_string(input))
    })
  }
}
