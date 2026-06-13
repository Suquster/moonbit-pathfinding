// prop_diff_test.mbt —— Property 2：多引擎差分一致性（任务 8.5）。
//
// Feature: regex-engine, Property 2: 多引擎差分一致性
//
// 对任意受支持子集正则与任意输入，五条执行路径——`Nfa::find`、`to_dfa` 后
// `Dfa::find`、`Dfa::minimize` 后 DFA、`LazyDfa::find`、`Ast::of_regex` 喂入
// Pike VM（`LeftmostLongest`）——给出逐字段相等的整体匹配区间。综合验证确定化、
// 最小化、惰性构造与 Pike VM 在最左最长策略下保持匹配语义一致。
//
// **Validates: Requirements 2.6, 7.4, 7.5, 7.6, 4.2**
//
// 复用 prop_nfa_dfa_test.mbt 的生成器 `gen_regex_at` / `gen_input_str`（同属
// 本包黑盒测试），≥100 迭代（holds_for_all 默认 iters=100）。

///|
/// 联合生成器：随机正则（深度 ≤3）与短随机输入（长度 ≤6）。
fn gen_diff_case() -> @infra_pbt.Gen[(Regex, String)] {
  @infra_pbt.Gen::new(fn(rng) {
    let r = gen_regex_at(rng, 3)
    let s = gen_input_str(rng, 6)
    (r, s)
  })
}

///|
/// 代表性见证：五路在确定性夹具上整体匹配区间一致。
test "five engines agree on representative witnesses" {
  let cases : Array[(String, String)] = [
    ("a(b|c)*d", "abcbcd"),
    ("[a-c]+", "xaabbz"),
    ("[^0-9]+", "ab12cd"),
    ("^a.*", "a"),
    ("a{2,3}", "aaaa"),
    ("(ab)+", "ababab"),
    ("a*b*", "aaabbb"),
    ("(a|b)*abb", "aabb"),
  ]
  for c in cases {
    let (pat, input) = c
    let r = match parse_regex(pat) {
      Ok(rr) => rr
      Err(_) => Char('\u{0}')
    }
    let nfa = build_nfa(r)
    let dfa = to_dfa(nfa)
    let mindfa = dfa.minimize()
    let lazy_dfa = LazyDfa::new(nfa)
    let prog = compile_program(Ast::of_regex(r))
    let m_nfa = nfa.find(input)
    let m_pike = match prog.exec(input, kind=LeftmostLongest) {
      Some(caps) => caps.group(0)
      None => None
    }
    assert_true(m_nfa == dfa.find(input))
    assert_true(m_nfa == mindfa.find(input))
    assert_true(m_nfa == lazy_dfa.find(input))
    assert_true(m_nfa == m_pike)
  }
}

///|
/// Feature: regex-engine, Property 2: 多引擎差分一致性
///
/// **Validates: Requirements 2.6, 7.4, 7.5, 7.6, 4.2**
test "Feature: regex-engine, Property 2: five engines agree on overall match" {
  let ok = @infra_pbt.holds_for_all(gen_diff_case(), fn(pair) {
    let (r, s) = pair
    let nfa = build_nfa(r)
    let dfa = to_dfa(nfa)
    let mindfa = dfa.minimize()
    let lazy_dfa = LazyDfa::new(nfa)
    let prog = compile_program(Ast::of_regex(r))
    let m_nfa = nfa.find(s)
    let m_dfa = dfa.find(s)
    let m_min = mindfa.find(s)
    let m_lazy = lazy_dfa.find(s)
    let m_pike = match prog.exec(s, kind=LeftmostLongest) {
      Some(caps) => caps.group(0)
      None => None
    }
    m_nfa == m_dfa && m_dfa == m_min && m_min == m_lazy && m_lazy == m_pike
  })
  assert_true(ok)
}
