// lazy_dfa_test.mbt —— 惰性 DFA `LazyDfa` 单元测试（任务 8.4）。
//
// 覆盖入口、状态缓存命中、与完整 `to_dfa` 对代表输入判定一致（R7.3/7.4）。

///|
/// 解析合法正则的测试辅助。
fn pr_lazy(s : String) -> Regex {
  match parse_regex(s) {
    Ok(r) => r
    Err(_) => Char('\u{0}')
  }
}

///|
/// 惰性 DFA 与完整子集构造 DFA 对一组代表输入给出一致匹配区间（R7.4）。
test "LazyDfa::find agrees with to_dfa on fixtures" {
  let patterns = [
    "a", "ab", "a|b", "a*", "a+", "a?", "a{2,3}", "[a-c]+", "[^0-9]+", "^a", "a$",
    "^ab$", "(ab)+", "a(b|c)*d", "x*y*z*",
  ]
  let inputs = [
    "", "a", "ab", "abc", "baaa", "12ab3", "ababx", "xbca", "zzz", "aaaa",
  ]
  for p in patterns {
    let nfa = build_nfa(pr_lazy(p))
    let dfa = to_dfa(nfa)
    let lazy_dfa = LazyDfa::new(nfa)
    for s in inputs {
      assert_true(lazy_dfa.find(s) == dfa.find(s))
    }
  }
}

///|
/// 状态缓存跨调用复用：多次 find 后已物化状态单调累积且有界。
test "LazyDfa caches states across calls" {
  let nfa = build_nfa(pr_lazy("a(b|c)*d"))
  let lazy_dfa = LazyDfa::new(nfa)
  let _ = lazy_dfa.find("abcbcd")
  let after_first = lazy_dfa.cores.length()
  assert_true(after_first > 0)
  let _ = lazy_dfa.find("ad")
  // 缓存复用：核数单调不减且保持有界（不超过完整 DFA 状态数）。
  assert_true(lazy_dfa.cores.length() >= after_first)
  let dfa = to_dfa(nfa)
  assert_true(lazy_dfa.cores.length() <= dfa.num_states)
}
