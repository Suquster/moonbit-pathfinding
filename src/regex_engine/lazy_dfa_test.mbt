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

///|
/// 缓存淘汰一致性（R7.3）：在极小状态预算（max_states=1，每步刷新）下，
/// `find_with_limit` 的匹配结果与默认 `find`（不触发淘汰）以及完整 `to_dfa`
/// 对同一 (正则, 输入) 逐位相等——证明缓存淘汰仅影响内存，不影响语义。
test "LazyDfa::find_with_limit eviction preserves match semantics" {
  let patterns = [
    "a", "ab", "a|b", "a*", "a+", "a?", "a{2,3}", "[a-c]+", "[^0-9]+", "^a", "a$",
    "^ab$", "(ab)+", "a(b|c)*d", "x*y*z*",
  ]
  let inputs = [
    "", "a", "ab", "abc", "baaa", "12ab3", "ababx", "xbca", "zzz", "aaaa", "abcbcd",
  ]
  for p in patterns {
    let nfa = build_nfa(pr_lazy(p))
    let dfa = to_dfa(nfa)
    for s in inputs {
      // 每个 (p, s) 用全新 LazyDfa，分别以「极小预算」与「默认预算」匹配。
      let lazy_tiny = LazyDfa::new(build_nfa(pr_lazy(p)))
      let lazy_def = LazyDfa::new(build_nfa(pr_lazy(p)))
      let r_tiny = lazy_tiny.find_with_limit(s, 1)
      let r_def = lazy_def.find(s)
      let r_ref = dfa.find(s)
      assert_true(r_tiny == r_ref)
      assert_true(r_tiny == r_def)
      // 极小预算下内存有界：刷新后物化状态数恒被约束在很小的常量内。
      assert_true(lazy_tiny.cores.length() <= 2)
    }
    let _ = nfa
  }
}

///|
/// 缓存淘汰的内存上界（R7.3）：给定预算 B，任意匹配过程中已物化状态数不超过
/// B + 1（刷新发生在 intern 之前，刷新后至多再 intern 一个核）。
test "LazyDfa eviction keeps materialized states within budget" {
  let nfa = build_nfa(pr_lazy("a(b|c)*d"))
  let budget = 3
  let lazy_dfa = LazyDfa::new(nfa)
  let _ = lazy_dfa.find_with_limit("abcbcbcbcbcbcd", budget)
  assert_true(lazy_dfa.cores.length() <= budget + 1)
}
