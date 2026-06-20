// hybrid_test.mbt —— 混合匹配器 `HybridMatcher` 内联烟雾测试（任务 5.3）。
//
// 仅做少量代表性用例验证：结果恒等于 `Nfa::find`，且容量充足（走 DFA 缓存）
// 与极小容量（频繁回退 NFA）下行为一致。完整属性测试见任务 5.4。

///|
/// 解析合法正则的测试辅助。
fn pr_hybrid(s : String) -> Regex {
  match parse_regex(s) {
    Ok(r) => r
    Err(_) => Char('\u{0}')
  }
}

///|
/// 混合匹配器对一组代表输入与多种容量（含极小 cap 强制回退）均与 `Nfa::find`
/// 给出一致匹配区间（AC3/AC4 与 5.4 核心不变量）。
test "HybridMatcher::find agrees with Nfa::find across caps" {
  let patterns = [
    "a", "ab", "a|b", "a*", "a+", "a?", "a{2,3}", "[a-c]+", "[^0-9]+", "^a", "a$",
    "^ab$", "(ab)+", "a(b|c)*d", "x*y*z*",
  ]
  let inputs = [
    "", "a", "ab", "abc", "baaa", "12ab3", "ababx", "xbca", "zzz", "aaaa", "abcbcd",
  ]
  // cap=0：纯 NFA 回退；cap=1/2：频繁切换；cap=1000：基本走 DFA 缓存。
  let caps = [0, 1, 2, 1000]
  for p in patterns {
    let nfa = build_nfa(pr_hybrid(p))
    for cap in caps {
      let hybrid = HybridMatcher::new(nfa, cap~)
      for s in inputs {
        assert_true(hybrid.find(s) == nfa.find(s))
      }
    }
  }
}
