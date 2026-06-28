// prop_prefilter_test.mbt —— 字面量预过滤差分一致性（T2.1，对标 Rust regex / RE2）。
//
// Feature: regex-engine, Property: literal prefilter correctness invariant
//
// 字面量预过滤只是「跳过绝不可能成为匹配起点的位置」的性能优化，**不得改变任何
// 匹配语义**。本属性以差分测试守护该不变量：对任意受支持子集正则与任意输入，
// 「开启预过滤」与「禁用预过滤（`without_prefilter`）」两条路径在
// `exec` 整体 + 各捕获组、`find` / `find_all` / `is_match` 上**逐位/逐字段相等**。
//
// **Validates: Requirements 2.6, 7.4, 7.5, 8.1, 8.2**
//
// 复用 prop_nfa_dfa_test.mbt 的生成器 `gen_regex_at` / `gen_input_str`（同包黑盒
// 测试）。差分类属性按纲领 DoD 取 ≥200 迭代。

///|
/// 比较两个 `Captures?` 的整体匹配与前若干捕获组是否逐字段相等。
/// 预过滤不改变捕获语义，故 group(0..=9) 必在两条路径上一致。
fn prefilter_caps_eq(a : Captures?, b : Captures?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(ca), Some(cb)) => {
      for i in 0..<10 {
        if ca.group(i) != cb.group(i) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// 联合生成器：随机正则（深度 ≤3）与短随机输入（长度 ≤8）。
fn gen_prefilter_case() -> @infra_pbt.Gen[(Regex, String)] {
  @infra_pbt.Gen::new(fn(rng) {
    let r = gen_regex_at(rng, 3)
    let s = gen_input_str(rng, 8)
    (r, s)
  })
}

///|
/// Program 级差分：开/关预过滤在两种匹配策略下 `exec` 结果逐字段相等。
///
/// **Validates: Requirements 2.6, 8.1, 8.2**
test "Feature: regex-engine, Property: prefilter preserves exec semantics" {
  let ok = @infra_pbt.holds_for_all(
    gen_prefilter_case(),
    fn(pair) {
      let (r, s) = pair
      let prog = compile_program(Ast::of_regex(r))
      let prog_off = prog.without_prefilter()
      let mut all = true
      for kind in [MatchKind::LeftmostLongest, MatchKind::LeftmostFirst] {
        let on = prog.exec(s, kind~)
        let off = prog_off.exec(s, kind~)
        if !prefilter_caps_eq(on, off) {
          all = false
        }
      }
      all
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// Pattern 级差分：开/关预过滤在 `find` / `find_all` / `is_match` 上完全一致。
///
/// **Validates: Requirements 8.1, 8.2**
test "Feature: regex-engine, Property: prefilter preserves high-level search" {
  let ok = @infra_pbt.holds_for_all(
    gen_prefilter_case(),
    fn(pair) {
      let (r, s) = pair
      // 经 print → compile 回到公共 Pattern API；解析失败的边角样本跳过（视为通过）。
      match Pattern::compile(print_regex(r)) {
        Err(_) => true
        Ok(pat) => {
          let off = pat.without_prefilter()
          pat.find(s) == off.find(s) &&
          pat.find_all(s) == off.find_all(s) &&
          pat.is_match(s) == off.is_match(s)
        }
      }
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// 代表性见证：覆盖预过滤的关键分支（字面前缀 / 字符类前缀 / 选择 / 可空退化 /
/// 锚点 / 忽略大小写 / 稀疏长文本 / 无候选起点提前终止）。
test "prefilter representative witnesses agree with no-prefilter" {
  let cases : Array[(String, String)] = [
    // 字面量前缀：稀疏命中的长文本（预过滤主战场）。
    ("error", "info info info info warn warn debug error trace"),
    ("needle", "haystack haystack haystack haystack haystack"),
    // 字符类前缀。
    ("[0-9]+", "abcdef ghijk 42 lmnop"),
    ("[A-Z][a-z]+", "...... Hello ...... World"),
    // 选择：多首字符并集。
    ("cat|dog|bird", "the lazy dog jumped"),
    ("(ab|cd)+", "xxxxabcdabxx"),
    // 可空 => 退化为无预过滤（不得提前终止/跳过）。
    ("a*", "bbbb"),
    ("x?y?", "zzz"),
    (".*", ""),
    // 锚点前导（零宽，不消费）。
    ("^foo", "foobar"),
    ("^[0-9]+$", "12345"),
    // 量词下界 >=1：首字符确定。
    ("a{2,3}b", "zzaaab"),
    // 全程无候选起点：应快速返回无匹配。
    ("zzz", "aaaaaaaaaaaaaaaaaaaa"),
    // 空输入。
    ("abc", ""),
  ]
  for c in cases {
    let (pat_s, input) = c
    let pat = match Pattern::compile(pat_s) {
      Ok(p) => p
      Err(_) => abort("unexpected parse error: " + pat_s)
    }
    let off = pat.without_prefilter()
    assert_true(pat.find(input) == off.find(input))
    assert_true(pat.find_all(input) == off.find_all(input))
    assert_true(pat.is_match(input) == off.is_match(input))
  }
}

///|
/// 忽略大小写：预过滤首字符集必须 case-fold，否则会漏过合法起点。
/// 这是 case-fold 超集不变量的专门见证。
test "prefilter respects ignore_case folding" {
  let flags = { ..Flags::default(), ignore_case: true }
  let pat = match Pattern::compile("hello", flags~) {
    Ok(p) => p
    Err(_) => abort("parse error")
  }
  let off = pat.without_prefilter()
  let inputs = ["HELLO world", "say Hello there", "xxHELLOxx", "no match here"]
  for s in inputs {
    assert_true(pat.find(s) == off.find(s))
    assert_true(pat.is_match(s) == off.is_match(s))
  }
}
