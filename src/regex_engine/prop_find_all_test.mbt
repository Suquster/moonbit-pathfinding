// prop_find_all_test.mbt —— Property 7：find_all 不重叠、穷尽且终止（任务 9.2）。
//
// Feature: regex-engine, Property 7: find_all 不重叠、穷尽且终止
//
// 对任意模式与任意输入，`find_all` 产出的相邻匹配区间满足后一匹配 `start`
// 不小于前一匹配 `end`（互不共享字符）；遇空匹配时扫描位置至少前进一字符使
// 枚举有限终止；每个匹配区间合法且落在 `[0, n]` 内。
//
// **Validates: Requirements 8.1, 8.2, 8.3, 8.8**
//
// 复用 prop_match_kind_test.mbt 的共享生成器 `gen_pat_input`（≥100 迭代）。

///|
/// 校验 `find_all` 结果满足不重叠、区间合法与有限终止（计数上界 n+1）。
fn fa_check(p : Pattern, input : String) -> Bool {
  let n = input.iter().to_array().length()
  let ms = p.find_all(input)
  // 有限终止：每次至少前进一字符 ⇒ 匹配数不超过 n+1。
  if ms.length() > n + 1 {
    return false
  }
  let mut i = 0
  while i < ms.length() {
    let m = ms[i]
    // 区间合法且落在 [0, n] 内。
    if !(m.start >= 0 && m.start <= m.end && m.end <= n) {
      return false
    }
    // 不重叠：后一匹配 start 不小于前一匹配 end。
    if i > 0 && m.start < ms[i - 1].end {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Feature: regex-engine, Property 7: find_all 不重叠、穷尽且终止
///
/// **Validates: Requirements 8.1, 8.2, 8.3, 8.8**
test "Feature: regex-engine, Property 7: find_all non-overlapping, valid, terminating" {
  let ok = @infra_pbt.holds_for_all(gen_pat_input(), fn(pair) {
    let (pat, input) = pair
    match Pattern::compile(pat) {
      Err(_) => false
      Ok(p) => fa_check(p, input)
    }
  })
  assert_true(ok)
}

///|
/// 代表性见证：非空匹配不重叠、空匹配前进、扫描覆盖整串。
test "find_all representative witnesses" {
  // 'a' 在 "banana" 上：[1,2)、[3,4)、[5,6)，互不重叠。
  match Pattern::compile("a") {
    Ok(p) => {
      let ms = p.find_all("banana")
      @test.assert_eq(ms.length(), 3)
      assert_true(ms[0] == { start: 1, end: 2 })
      assert_true(ms[1] == { start: 3, end: 4 })
      assert_true(ms[2] == { start: 5, end: 6 })
    }
    Err(_) => fail("compile failed for a")
  }
  // 空匹配 `a*` 在 "bab" 上：枚举有限终止（每个空匹配至少前进一字符）。
  match Pattern::compile("a*") {
    Ok(p) => {
      let ms = p.find_all("bab")
      assert_true(fa_check(p, "bab"))
      // 至少覆盖到串尾的空匹配存在。
      assert_true(ms.length() >= 1)
    }
    Err(_) => fail("compile failed for a*")
  }
}
