// prop_charset_lazydfa_test.mbt —— 旗舰深化优化的属性测试（≥100 迭代）。
//
// 本文件以全称量化属性固化本轮两项性能优化的**正确性不变量**，复用 @infra_pbt
// 的种子驱动随机源 `Rng` 与 `holds_for_all`（默认 100 次迭代，满足 ≥100 基线，
// 三后端逐位一致可重放）：
//
//   * Property A「CharSet 二分查找等价」：`CharSet::contains`（二分查找实现）
//     对任意归一化字符集合与任意码点，与朴素线性扫描参照逐点相等——证明二分
//     优化未改变判定语义（R5）。
//   * Property B「惰性 DFA 缓存淘汰一致」：`LazyDfa::find_with_limit` 在极小
//     状态预算（每步刷新）下，与完整子集构造 `Dfa::find` 对任意正则与输入给出
//     逐字段相等的匹配区间——证明缓存淘汰仅影响内存、不影响语义（R7.3/7.4）。

// ---------------------------------------------------------------------------
// Property A：CharSet 二分查找等价于线性扫描
// ---------------------------------------------------------------------------

///|
/// 朴素线性扫描参照实现：逐区间判定码点是否落入（用作二分查找的差分基准）。
fn cs_contains_linear_ref(cs : CharSet, code : Int) -> Bool {
  for iv in cs.intervals {
    let (lo, hi) = iv
    if code >= lo && code <= hi {
      return true
    }
  }
  false
}

///|
/// 随机「归一化字符集合 + 码点」生成器。
///
/// 直接构造满足 `CharSet` 不变量（升序、不相交、不相邻）的区间序列：从随机起点
/// 出发，每个后继区间起点较前一区间终点至少 +2（保证不相交且不相邻），区间长度
/// 随机。如此产出的 `CharSet` 与生产代码经 `normalize_intervals` 得到的形态一致，
/// 且无需依赖包私有的 `normalize_intervals`（黑盒测试不可见）。码点取值范围刻意
/// 覆盖区间上下界之外，以充分检验「区间外（含小于最小、大于最大）」分支。
fn gen_charset_and_code() -> @infra_pbt.Gen[(CharSet, Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_below(6)
    let intervals : Array[(Int, Int)] = []
    let mut cursor = rng.next_range(0, 5)
    for _i in 0..<n {
      // 起点较前一终点至少 +2，保证升序、不相交且不相邻（归一化形态）。
      let lo = cursor + rng.next_range(2, 5)
      let hi = lo + rng.next_below(8)
      intervals.push((lo, hi))
      cursor = hi
    }
    let cs : CharSet = { intervals, }
    let code = rng.next_range(-3, cursor + 6)
    (cs, code)
  })
}

///|
/// Feature: moonbit-infra-suite, Property A: CharSet 二分查找等价于线性扫描
///
/// 对任意归一化字符集合 `cs` 与任意码点 `code`，二分查找 `cs.contains(code)`
/// 与线性扫描参照 `cs_contains_linear_ref(cs, code)` 恒相等。
///
/// **Validates: Requirements 5（CharSet 二分查找性能优化的语义保持）**
test "Feature: moonbit-infra-suite, Property A: CharSet binary-search contains equals linear reference" {
  let ok = @infra_pbt.holds_for_all(gen_charset_and_code(), fn(pair) {
    let (cs, code) = pair
    cs.contains(code) == cs_contains_linear_ref(cs, code)
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property B：惰性 DFA 缓存淘汰保持匹配语义
// ---------------------------------------------------------------------------

///|
/// 随机「正则语法树 + 输入串」生成器（本文件局部，规模与 prop_nfa_dfa 一致，
/// 复用其包内可见的 `gen_regex_at` / `gen_input_str` 叶子生成器）。
fn gen_regex_and_input_for_eviction() -> @infra_pbt.Gen[(Regex, String)] {
  @infra_pbt.Gen::new(fn(rng) {
    let r = gen_regex_at(rng, 3)
    let s = gen_input_str(rng, 7)
    (r, s)
  })
}

///|
/// Feature: moonbit-infra-suite, Property B: 惰性 DFA 缓存淘汰保持匹配语义
///
/// 对任意受支持子集正则 `r` 与任意输入 `s`，惰性 DFA 在极小状态预算
/// （`max_states=1`，每步刷新缓存）下的匹配结果，与完整子集构造 DFA
/// `Dfa::find` 逐字段相等——证明缓存淘汰仅影响内存占用、不影响匹配语义。
///
/// **Validates: Requirements 7.3, 7.4**
test "Feature: moonbit-infra-suite, Property B: LazyDfa eviction preserves match semantics" {
  let ok = @infra_pbt.holds_for_all(gen_regex_and_input_for_eviction(), fn(
    pair,
  ) {
    let (r, s) = pair
    let nfa = build_nfa(r)
    let dfa = to_dfa(nfa)
    let lazy_dfa = LazyDfa::new(build_nfa(r))
    lazy_dfa.find_with_limit(s, 1) == dfa.find(s)
  })
  assert_true(ok)
}
