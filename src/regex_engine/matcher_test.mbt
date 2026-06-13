// matcher_test.mbt —— Regex_Engine 任务 6.2 的单元测试。
//
// 覆盖 `build_nfa`（Thompson 构造）、`to_dfa`（子集构造确定化）与 `find`
// （返回是否匹配 + 匹配区间，R2.4 / R2.5）：典型匹配、不匹配、匹配区间
// 边界，以及 NFA 与 DFA 两条路径的一致性自洽（为任务 6.4 差分一致性奠基；
// 完整属性测试属任务 6.4，本文件仅做小型确定性夹具校验）。
//
// 说明：对 `Match` / `Result` 等复合类型采用 `assert_true(x == y)`（走派生
// `Eq`），避免触发 `Show`-用于-debug 的弃用告警，保持本包零告警。

///|
/// 解析合法正则的测试辅助：测试用例均为受支持子集内的合法表达式，故
/// `Err` 分支不可达（以一个哨兵语法树兜底以满足类型）。
fn pr(s : String) -> Regex {
  match parse_regex(s) {
    Ok(r) => r
    Err(_) => Char('\u{0}')
  }
}

// ---------------------------------------------------------------------------
// 基础匹配与匹配区间（R2.5）
// ---------------------------------------------------------------------------

///|
/// 单字符匹配，区间为 [0,1)。
test "find single char match interval" {
  assert_true(find(pr("a"), "a") == Some({ start: 0, end: 1 }))
}

///|
/// 单字符不匹配返回 None。
test "find single char no match" {
  assert_true(find(pr("a"), "b") == None)
}

///|
/// 最左匹配：在串中部命中，返回最左起点的区间。
test "find leftmost occurrence" {
  assert_true(find(pr("a"), "bca") == Some({ start: 2, end: 3 }))
}

///|
/// 串接匹配返回完整区间。
test "find concatenation interval" {
  assert_true(find(pr("ab"), "xaby") == Some({ start: 1, end: 3 }))
}

///|
/// 择一匹配任一分支。
test "find alternation branch" {
  assert_true(find(pr("a|b"), "cb") == Some({ start: 1, end: 2 }))
}

// ---------------------------------------------------------------------------
// 量词：最左最长（leftmost-longest）语义
// ---------------------------------------------------------------------------

///|
/// `a*` 在 "aaa" 上取最长，区间 [0,3)。
test "find star longest" {
  assert_true(find(pr("a*"), "aaa") == Some({ start: 0, end: 3 }))
}

///|
/// `a*` 可匹配空串：在 "b" 上于起点 0 命中空匹配 [0,0)。
test "find star empty match at start" {
  assert_true(find(pr("a*"), "b") == Some({ start: 0, end: 0 }))
}

///|
/// `a+` 需至少一次：跳过前导 'b'，在 "baaa" 上命中 [1,4)。
test "find plus skips non-match prefix" {
  assert_true(find(pr("a+"), "baaa") == Some({ start: 1, end: 4 }))
}

///|
/// `a?` 在 "b" 上于起点 0 命中空匹配。
test "find optional empty match" {
  assert_true(find(pr("a?"), "b") == Some({ start: 0, end: 0 }))
}

///|
/// 计数量词 `a{2}` 恰好两次。
test "find counted exact" {
  assert_true(find(pr("a{2}"), "aaa") == Some({ start: 0, end: 2 }))
}

///|
/// 计数量词 `a{2,3}` 取上界 3。
test "find counted range longest" {
  assert_true(find(pr("a{2,3}"), "aaaa") == Some({ start: 0, end: 3 }))
}

///|
/// 计数量词 `a{2,}` 无上界，吞尽连续 'a'。
test "find counted lower bound unbounded" {
  assert_true(find(pr("a{2,}"), "aaaa") == Some({ start: 0, end: 4 }))
}

// ---------------------------------------------------------------------------
// 字符类与范围 / 否定
// ---------------------------------------------------------------------------

///|
/// 字符类范围 `[a-c]+` 在 "xbca" 上跳过 'x'，命中 [1,4)。
test "find char class range" {
  assert_true(find(pr("[a-c]+"), "xbca") == Some({ start: 1, end: 4 }))
}

///|
/// 否定字符类 `[^0-9]+` 匹配连续非数字，遇数字停止。
test "find negated char class" {
  assert_true(find(pr("[^0-9]+"), "12ab3") == Some({ start: 2, end: 4 }))
}

// ---------------------------------------------------------------------------
// 锚点 ^ / $
// ---------------------------------------------------------------------------

///|
/// `^a` 仅在串首命中。
test "find start anchor matches at start" {
  assert_true(find(pr("^a"), "ab") == Some({ start: 0, end: 1 }))
}

///|
/// `^a` 在非串首处不命中。
test "find start anchor no match off start" {
  assert_true(find(pr("^a"), "ba") == None)
}

///|
/// `a$` 仅在串尾命中。
test "find end anchor matches at end" {
  assert_true(find(pr("a$"), "ba") == Some({ start: 1, end: 2 }))
}

///|
/// `a$` 在非串尾处不命中。
test "find end anchor no match off end" {
  assert_true(find(pr("a$"), "ab") == None)
}

///|
/// 全锚定 `^ab$` 要求整串恰为 "ab"。
test "find fully anchored exact" {
  assert_true(find(pr("^ab$"), "ab") == Some({ start: 0, end: 2 }))
  assert_true(find(pr("^ab$"), "abc") == None)
}

// ---------------------------------------------------------------------------
// 转义、分组与空正则
// ---------------------------------------------------------------------------

///|
/// 转义元字符作为字面字符匹配。
test "find escaped metacharacter" {
  assert_true(find(pr("a\\+"), "a+") == Some({ start: 0, end: 2 }))
}

///|
/// 分组配合量词 `(ab)+`。
test "find grouped plus" {
  assert_true(find(pr("(ab)+"), "ababx") == Some({ start: 0, end: 4 }))
}

///|
/// 空正则匹配空串，区间 [0,0)。
test "find empty regex matches empty" {
  assert_true(find(pr(""), "abc") == Some({ start: 0, end: 0 }))
}

///|
/// `is_match` 便捷判定。
test "is_match convenience" {
  assert_true(is_match(pr("a|b"), "zzb"))
  assert_true(!is_match(pr("a"), "zzz"))
}

// ---------------------------------------------------------------------------
// 自动机构造形态与 NFA/DFA 一致性自洽
// ---------------------------------------------------------------------------

///|
/// `build_nfa` 产出非空状态集，且接受状态有效。
test "build_nfa basic shape" {
  let nfa = build_nfa(pr("a(b|c)*"))
  assert_true(nfa.num_states > 0)
  assert_true(nfa.start >= 0 && nfa.start < nfa.num_states)
  assert_true(nfa.accept >= 0 && nfa.accept < nfa.num_states)
}

///|
/// `to_dfa` 产出非空状态集。
test "to_dfa basic shape" {
  let dfa = to_dfa(build_nfa(pr("a(b|c)*")))
  assert_true(dfa.num_states > 0)
  assert_true(dfa.start >= 0 && dfa.start < dfa.num_states)
}

///|
/// NFA 与 DFA 两条匹配路径在一组确定性夹具上结果一致（任务 6.4 差分一致性
/// 的局部自洽校验）。
test "nfa and dfa agree on fixtures" {
  let patterns = [
    "a", "ab", "a|b", "a*", "a+", "a?", "a{2,3}", "[a-c]+", "[^0-9]+", "^a", "a$",
    "^ab$", "(ab)+", "a(b|c)*d", "x*y*z*",
  ]
  let inputs = [
    "", "a", "ab", "abc", "baaa", "12ab3", "ababx", "xbca", "aBcd", "zzz",
  ]
  for p in patterns {
    let r = pr(p)
    let nfa = build_nfa(r)
    let dfa = to_dfa(nfa)
    for s in inputs {
      assert_true(nfa.find(s) == dfa.find(s))
      assert_true(find(r, s) == dfa.find(s))
    }
  }
}
