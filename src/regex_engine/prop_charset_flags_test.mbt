// prop_charset_flags_test.mbt —— Property 9：预定义字符类与标志的 CharSet 语义
// （任务 1.4）。
//
// Feature: regex-engine, Property 9: 预定义字符类与标志的 CharSet 语义
//
// 以属性（全称量化）校验：对任意码点 `c`，`\d`/`\w`/`\s` 的成员判定等于其
// 参考谓词，`\D`/`\W`/`\S` 恒为对应正向类在 [0, MAX_CODE] 上的精确补集；
// 点号 `.` 在 dotall 关 / 开时分别不含 / 含 `\n`；大小写不敏感（`i`）折叠集合
// 同时含大小写两形态；所有字符集合均满足归一化、不相交、升序不变量。
//
// **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.7**
//
// 复用 @infra_pbt 种子驱动随机源（≥100 迭代，由 holds_for_all 默认 iters=100
// 保证），生成器覆盖 ASCII 边界码点与偶发大码点（验证补集在 ASCII 之外）。

// ---------------------------------------------------------------------------
// 参考谓词（reference predicates）—— ASCII 约定
// ---------------------------------------------------------------------------

///|
/// `\d` 参考谓词：码点落在 `'0'..'9'`。
fn ref_is_digit(c : Int) -> Bool {
  c >= '0'.to_int() && c <= '9'.to_int()
}

///|
/// `\w` 参考谓词：数字 / 大写 / 小写字母 / 下划线。
fn ref_is_word(c : Int) -> Bool {
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  c == '_'.to_int()
}

///|
/// `\s` 参考谓词：制表 / 换行 / 垂直制表 / 换页 / 回车（9..13）与空格（32）。
fn ref_is_space(c : Int) -> Bool {
  (c >= 9 && c <= 13) || c == 32
}

// ---------------------------------------------------------------------------
// CharSet 不变量校验：归一化、不相交、升序
// ---------------------------------------------------------------------------

///|
/// 校验字符集合区间满足：每段 `lo <= hi`，且相邻两段严格不相交且不相邻
/// （后段 `lo > 前段 hi + 1`），整体升序。
fn cs_is_normalized(cs : CharSet) -> Bool {
  let ivs = cs.intervals
  for i in 0..<ivs.length() {
    let (lo, hi) = ivs[i]
    if lo > hi {
      return false
    }
    if i > 0 {
      let (_, phi) = ivs[i - 1]
      if lo <= phi + 1 {
        return false
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// 码点生成器（generator）
// ---------------------------------------------------------------------------

///|
/// 码点生成器：约 4/5 概率取 ASCII 范围 [0, 255]（覆盖类边界），其余取
/// 全码点范围 [0, MAX_CODE]（验证补集在 ASCII 之外的行为）。MAX_CODE =
/// U+10FFFF，与 nfa.mbt 的码点上界一致。
fn gen_codepoint() -> @infra_pbt.Gen[Int] {
  @infra_pbt.Gen::new(fn(rng) {
    if rng.next_below(5) == 0 {
      rng.next_range(0, 0x10FFFF)
    } else {
      rng.next_below(256)
    }
  })
}

// ---------------------------------------------------------------------------
// Property 9（≥100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: regex-engine, Property 9: 预定义字符类与标志的 CharSet 语义
///
/// **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.7**
test "Feature: regex-engine, Property 9: predefined classes and flags CharSet semantics" {
  let digit = predef_digit()
  let non_digit = predef_non_digit()
  let word = predef_word()
  let non_word = predef_non_word()
  let space = predef_space()
  let non_space = predef_non_space()
  let dot_off = Flags::default().dot_set()
  let dot_on = Flags::parse("s").dot_set()
  // 不变量：所有预定义集合归一化。
  assert_true(cs_is_normalized(digit))
  assert_true(cs_is_normalized(non_digit))
  assert_true(cs_is_normalized(word))
  assert_true(cs_is_normalized(non_word))
  assert_true(cs_is_normalized(space))
  assert_true(cs_is_normalized(non_space))
  assert_true(cs_is_normalized(dot_off))
  assert_true(cs_is_normalized(dot_on))
  let ok = @infra_pbt.holds_for_all(gen_codepoint(), fn(c) {
    // 成员判定等于参考谓词。
    let m1 = digit.contains(c) == ref_is_digit(c)
    let m2 = word.contains(c) == ref_is_word(c)
    let m3 = space.contains(c) == ref_is_space(c)
    // 否定类恒为精确补集。
    let m4 = non_digit.contains(c) == not(digit.contains(c))
    let m5 = non_word.contains(c) == not(word.contains(c))
    let m6 = non_space.contains(c) == not(space.contains(c))
    // 点号：dotall 关时不含 '\n'（10），开时含全部 [0, MAX_CODE]。
    let m7 = dot_off.contains(c) == (c != 10)
    let m8 = dot_on.contains(c) == true
    // 大小写折叠：单点集合折叠后同时含其大小写两形态。
    let single : CharSet = { intervals: [(c, c)] }
    let folded = single.case_fold()
    let m9 = folded.contains(c) &&
      cs_is_normalized(folded) &&
      (if c >= 'A'.to_int() && c <= 'Z'.to_int() {
        folded.contains(c + 32)
      } else {
        true
      }) &&
      (if c >= 'a'.to_int() && c <= 'z'.to_int() {
        folded.contains(c - 32)
      } else {
        true
      })
    m1 && m2 && m3 && m4 && m5 && m6 && m7 && m8 && m9
  })
  assert_true(ok)
}
