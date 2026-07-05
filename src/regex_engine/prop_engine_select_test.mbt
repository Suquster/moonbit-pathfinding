// prop_engine_select_test.mbt —— 引擎自动选择差分一致性（T2.3）。
//
// Feature: regex-engine, Property: engine auto-selection semantic invariant
//
// T2.3 的核心契约：无论查询被路由到字面量直扫、惰性 DFA 还是 Pike VM，
// `is_match` / `find` / `find_all` 的结果必须与强制 Pike VM 路径**逐位相等**。
// 本文件以差分属性测试 + 决策见证 + 代表性案例守护该不变量。
//
// **Validates: Requirements 2.6, 7.4, 7.5, 8.1, 8.2**

///|
/// 编译期决策见证：三类引擎在代表性模式上被正确选中，决策可观测。
test "select_engine routes patterns to the expected engine" {
  fn eng(p : String) -> EngineChoice {
    match Pattern::compile(p) {
      Ok(pat) => pat.engine
      Err(_) => abort("unexpected parse error: " + p)
    }
  }

  // 纯字面量 => 直扫。
  assert_true(eng("hello") is EngLiteralScan)
  assert_true(eng("a") is EngLiteralScan)
  // 无捕获、无断言 => 惰性 DFA。
  assert_true(eng("a+b*") is EngLazyDfa)
  assert_true(eng("error|warn|fatal") is EngLazyDfa)
  assert_true(eng("[0-9]+") is EngLazyDfa)
  // 捕获组 => Pike VM。
  assert_true(eng("(a)b") is EngPikeVm)
  // 零宽断言 / 前瞻 => Pike VM。
  assert_true(eng("^ab") is EngPikeVm)
  assert_true(eng("a\\b") is EngPikeVm)
  // 最左优先策略下非字面量 => Pike VM（DFA 无优先级语义）。
  match Pattern::compile("a|ab", kind=LeftmostFirst) {
    Ok(pat) => assert_true(pat.engine is EngPikeVm)
    Err(_) => abort("unexpected parse error")
  }
  // without_auto_engine：强制回 Pike VM。
  match Pattern::compile("hello") {
    Ok(pat) => assert_true(pat.without_auto_engine().engine is EngPikeVm)
    Err(_) => abort("unexpected parse error")
  }
}

///|
/// 差分 PBT：随机正则 × 随机输入下，自动路由与强制 Pike VM 在
/// `is_match` / `find` / `find_all` 上完全一致。
///
/// **Validates: Requirements 8.1, 8.2**
test "Feature: regex-engine, Property: engine routing preserves search semantics" {
  let ok = @infra_pbt.holds_for_all(
    gen_prefilter_case(),
    fn(pair) {
      let (r, s) = pair
      match Pattern::compile(print_regex(r)) {
        Err(_) => true
        Ok(pat) => {
          let pk = pat.without_auto_engine()
          pat.find(s) == pk.find(s) &&
          pat.find_all(s) == pk.find_all(s) &&
          pat.is_match(s) == pk.is_match(s)
        }
      }
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// 代表性见证：每类引擎的主战场与关键边界（空匹配推进、重叠候选、无命中、
/// 长输入多命中、可空模式）在自动路由与强制 Pike VM 下逐位一致。
test "engine routing representative witnesses agree with forced Pike VM" {
  let cases : Array[(String, String)] = [
    // 字面量直扫。
    ("hello", "say hello to hello world"),
    ("aa", "aaaaaa"),
    ("xyz", "no such needle"),
    ("a", ""),
    // 惰性 DFA：选择 / 量词 / 字符集。
    ("error|warn|fatal", "info warn debug error fatal"),
    ("[0-9]+", "a1b22c333"),
    ("a+b*", "xxaabbyyab"),
    ("a*", "bab"),
    ("(?:ab)+", "ababab zab"),
    // Pike VM：捕获 / 锚点 / 词边界。
    ("(a+)(b+)", "xaabbx"),
    ("^ab", "abab"),
    ("a\\b", "a b ab"),
  ]
  for c in cases {
    let (pat_s, input) = c
    let pat = match Pattern::compile(pat_s) {
      Ok(p) => p
      Err(_) => abort("unexpected parse error: " + pat_s)
    }
    let pk = pat.without_auto_engine()
    assert_true(pat.find(input) == pk.find(input))
    assert_true(pat.find_all(input) == pk.find_all(input))
    assert_true(pat.is_match(input) == pk.is_match(input))
  }
}
