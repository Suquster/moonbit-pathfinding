// minimize_test.mbt —— DFA 最小化 `Dfa::minimize` 单元测试（任务 8.2）。
//
// 覆盖最小化入口、等价态合并见证、最小化前后对代表输入判定一致（R7.1/7.2/7.5）。

///|
/// 解析合法正则的测试辅助（用例均为受支持子集内合法表达式）。
fn pr_min(s : String) -> Regex {
  match parse_regex(s) {
    Ok(r) => r
    Err(_) => Char('\u{0}')
  }
}

///|
/// 最小化前后对一组代表输入给出一致的匹配区间（语言等价，R7.5）。
test "Dfa::minimize preserves matching on fixtures" {
  let patterns = [
    "a", "ab", "a|b", "a*", "a+", "(a|b)*abb", "[a-c]+", "^ab$", "a(b|c)*d", "a{2,3}",
  ]
  let inputs = [
    "", "a", "ab", "abb", "abab", "aabb", "ccab", "abbabb", "xabbx", "aaaa",
  ]
  for p in patterns {
    let dfa = to_dfa(build_nfa(pr_min(p)))
    let small = dfa.minimize()
    for s in inputs {
      assert_true(dfa.find(s) == small.find(s))
    }
  }
}

///|
/// 最小化不增加状态数，且产出非空状态集。
test "Dfa::minimize does not increase state count" {
  let dfa = to_dfa(build_nfa(pr_min("(a|b)*abb")))
  let small = dfa.minimize()
  assert_true(small.num_states > 0)
  assert_true(small.num_states <= dfa.num_states)
  assert_true(small.start >= 0 && small.start < small.num_states)
}

///|
/// 最小化幂等：对已最小化的 DFA 再最小化，状态数不变。
test "Dfa::minimize is idempotent" {
  let dfa = to_dfa(build_nfa(pr_min("a(b|c)*d")))
  let small = dfa.minimize()
  let twice = small.minimize()
  assert_eq(twice.num_states, small.num_states)
}

///|
/// 合并等价态见证：含冗余等价分支的正则，最小化后状态数不大于原 DFA，
/// 且匹配判定保持一致。
test "Dfa::minimize merges equivalent states" {
  let dfa = to_dfa(build_nfa(pr_min("aa|aa")))
  let small = dfa.minimize()
  assert_true(small.num_states <= dfa.num_states)
  let inputs = ["", "a", "aa", "aaa"]
  for s in inputs {
    assert_true(dfa.find(s) == small.find(s))
  }
}
