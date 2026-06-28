// benches/regex_bench — Regex_Engine 旗舰深化性能基准与回归 guard。
//
// 对应 design.md §4.12（R9）。对三路执行计时：
//   * Nfa::find   —— Thompson NFA 邻接表执行；
//   * Dfa::find   —— 子集构造 DFA 执行；
//   * Program::exec —— Pike VM 线程列表执行（捕获）。
// 两类工作负载：
//   * 病态输入：`a?{n}a{n}` 应用于 `a^n`（Russ Cox 经典反例，回溯型引擎指数
//     爆炸；本库自动机 / Pike VM 保持线性）；
//   * 真实负载：复用 `demo_*` 实战模式 × 规模化输入。
//
// 回归 guard（R9.4）：
//   * 线性 guard —— 以 `Program::exec_steps` 测病态族在 n / 2n / 4n 的线程步数，
//     断言增长比落在声明容差内（指数回溯会远超），超限给出可审计失败报告；
//   * 真实负载 guard —— 规模化输入上 `find_all` 匹配计数对内联基线精确比较。
//
// 运行（R9.5）：
//   moon test  -p Suquster/moonbit-pathfinding/benches/regex_bench --target wasm-gc
//   moon bench -p Suquster/moonbit-pathfinding/benches/regex_bench --target native
// native 运行前须先：export LIBRARY_PATH=/usr/lib64:/usr/lib
//
// _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

// ---------------------------------------------------------------------------
// 工作负载构造
// ---------------------------------------------------------------------------

///|
/// 病态模式 `a?{rep}a{rep}`：`rep` 个 `a?` 后接 `rep` 个 `a`。
fn patho_pattern(rep : Int) -> String {
  let mut s = ""
  for _i in 0..<rep {
    s = s + "a?"
  }
  for _i in 0..<rep {
    s = s + "a"
  }
  s
}

///|
/// 病态输入 `a^rep`。
fn repeat_a(rep : Int) -> String {
  let mut s = ""
  for _i in 0..<rep {
    s = s + "a"
  }
  s
}

///|
/// 规模化真实负载：`sample` 以单空格连接 `copies` 份。
fn scaled_input(sample : String, copies : Int) -> String {
  let mut s = ""
  for i in 0..<copies {
    if i > 0 {
      s = s + " "
    }
    s = s + sample
  }
  s
}

// ---------------------------------------------------------------------------
// 比较辅助
// ---------------------------------------------------------------------------

///|
/// 逐字段比较两个可选匹配区间。
fn match_eq(a : @re.Match?, b : @re.Match?) -> Bool {
  match (a, b) {
    (Some(x), Some(y)) => x.start == y.start && x.end == y.end
    (None, None) => true
    _ => false
  }
}

// ---------------------------------------------------------------------------
// 冒烟 guard（correctness）：三路 + Pike VM 在病态负载上差分一致
// ---------------------------------------------------------------------------

///|
/// Smoke: 病态族在 Nfa::find / Dfa::find / 最小化 DFA / Pike VM 四路给出一致的
/// 整体匹配区间 `[0, rep]`（差分一致性保护基准工作负载，R9.1/R9.2）。
test "smoke: pathological workload differential consistency" {
  for rep in [4, 8, 12] {
    let pattern = patho_pattern(rep)
    let input = repeat_a(rep)
    let regex = match @re.parse_regex(pattern) {
      Ok(r) => r
      Err(_) => {
        fail("parse_regex failed for pathological pattern")
        return
      }
    }
    let nfa = @re.build_nfa(regex)
    let dfa = @re.to_dfa(nfa)
    let min_dfa = dfa.minimize()
    let nfa_m = nfa.find(input)
    let dfa_m = dfa.find(input)
    let min_m = min_dfa.find(input)
    // Pike VM 路径。
    let prog = match @re.parse_pattern(pattern) {
      Ok(ast) => @re.compile_program(ast)
      Err(_) => {
        fail("parse_pattern failed for pathological pattern")
        return
      }
    }
    let pike_m = match prog.exec(input) {
      Some(caps) => caps.group(0)
      None => None
    }
    // 四路一致且等于 [0, rep]。
    assert_true(match_eq(nfa_m, dfa_m))
    assert_true(match_eq(dfa_m, min_m))
    assert_true(match_eq(min_m, pike_m))
    match nfa_m {
      Some(m) => {
        @test.assert_eq(m.start, 0)
        @test.assert_eq(m.end, rep)
      }
      None => fail("pathological pattern did not match a^rep")
    }
  }
}

///|
/// Smoke: 真实负载（demo 模式）在规模化输入上每份样例命中一次（R9.2）。
test "smoke: real workload demo patterns match scaled input" {
  let copies = 8
  for case in @re.demo_cases() {
    let (pattern, sample) = case
    let p = match @re.Pattern::compile(pattern) {
      Ok(pat) => pat
      Err(_) => {
        fail("Pattern::compile failed for demo pattern: " + pattern)
        return
      }
    }
    let input = scaled_input(sample, copies)
    let ms = p.find_all(input)
    // 每份样例恰好一次不重叠匹配（空格分隔不被 demo 模式匹配）。
    @test.assert_eq(ms.length(), copies)
  }
}

// ---------------------------------------------------------------------------
// 回归 guard（R9.4）：线性步数界 + 真实负载匹配计数基线
// ---------------------------------------------------------------------------

///|
/// 线性 guard：Pike VM 在病态族上的线程步数随规模近似平方增长（正则规模 ×
/// 输入长度，二者均 ∝ n），故倍增 n 约 4 倍；声明容差比 = 8（指数回溯会达
/// 2^n 量级，远超）。超限给出可审计失败报告（R2.2 / R9.4）。
test "guard: pike vm step count stays within linear tolerance" {
  let tolerance_ratio = 8
  let sizes = [8, 16, 32]
  let steps : Array[Int] = []
  for rep in sizes {
    let pattern = patho_pattern(rep)
    let input = repeat_a(rep)
    let prog = match @re.parse_pattern(pattern) {
      Ok(ast) => @re.compile_program(ast)
      Err(_) => {
        fail("parse_pattern failed in step guard")
        return
      }
    }
    steps.push(prog.exec_steps(input))
  }
  // 绝对下界：步数为正。
  assert_true(steps[0] > 0)
  // 相邻倍增比落在容差内。
  let mut i = 1
  while i < steps.length() {
    let prev = steps[i - 1]
    let cur = steps[i]
    if cur > tolerance_ratio * prev {
      fail(
        "REGEX-BENCH GUARD FAIL [linearity]: step count " +
        "n=" +
        sizes[i - 1].to_string() +
        " -> " +
        sizes[i].to_string() +
        " grew " +
        prev.to_string() +
        " -> " +
        cur.to_string() +
        " (ratio > declared tolerance " +
        tolerance_ratio.to_string() +
        "x); possible loss of linear-time guarantee.",
      )
    }
    i = i + 1
  }
}

///|
/// 真实负载 guard：规模化输入上 `find_all` 匹配计数与内联基线（每模式恰
/// `copies` 次）精确比较；偏离给出可审计失败报告（R9.3/R9.4）。
test "guard: real workload match count matches baseline" {
  let copies = 16
  // 内联基线：每个 demo 模式在 `copies` 份样例上应恰命中 `copies` 次。
  for case in @re.demo_cases() {
    let (pattern, sample) = case
    let p = match @re.Pattern::compile(pattern) {
      Ok(pat) => pat
      Err(_) => {
        fail("Pattern::compile failed in count guard: " + pattern)
        return
      }
    }
    let input = scaled_input(sample, copies)
    let got = p.find_all(input).length()
    if got != copies {
      fail(
        "REGEX-BENCH GUARD FAIL [match-count]: pattern '" +
        pattern +
        "' produced " +
        got.to_string() +
        " matches on " +
        copies.to_string() +
        " scaled copies (baseline=" +
        copies.to_string() +
        ").",
      )
    }
  }
}

// ---------------------------------------------------------------------------
// 原生基准（@bench.T）：三路 × 两负载（moon bench 下执行）
// ---------------------------------------------------------------------------

///|
/// 病态负载：Nfa::find / Dfa::find / Program::exec 三路计时。
test "bench: pathological a?{n}a{n} three engines" (b : @bench.T) {
  let rep = 24
  let pattern = patho_pattern(rep)
  let input = repeat_a(rep)
  let regex = match @re.parse_regex(pattern) {
    Ok(r) => r
    Err(_) => return
  }
  let nfa = @re.build_nfa(regex)
  let dfa = @re.to_dfa(nfa)
  let prog = match @re.parse_pattern(pattern) {
    Ok(ast) => @re.compile_program(ast)
    Err(_) => return
  }
  b.bench(name="regex_patho_nfa_find", fn() { b.keep(nfa.find(input)) })
  b.bench(name="regex_patho_dfa_find", fn() { b.keep(dfa.find(input)) })
  b.bench(name="regex_patho_pikevm_exec", fn() { b.keep(prog.exec(input)) })
}

///|
/// 真实负载：demo 模式（email）规模化输入上的 Pike VM find_all 计时。
test "bench: real workload demo email pike vm find_all" (b : @bench.T) {
  let p = match @re.Pattern::compile(@re.demo_email()) {
    Ok(pat) => pat
    Err(_) => return
  }
  let input = scaled_input("user_1@example.com", 64)
  b.bench(name="regex_real_email_find_all", fn() { b.keep(p.find_all(input)) })
}
