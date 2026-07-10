// prop_error_test.mbt —— Regex_Engine 任务 6.5 的错误条件属性测试。
//
// Feature: moonbit-infra-suite, Property 6: Regex 非法表达式错误条件
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 6，复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all`
// 模板（每条属性 ≥100 次迭代，由 `holds_for_all` 默认 `iters=100` 保证）。
//
// 性质（design.md Property 6）：
//   *对任意* 语法非法的正则字符串，引擎应返回包含错误位置的解析错误，
//   且不构造任何自动机。
//
// **Validates: Requirements 2.3**
//
// 设计要点：
//   * `gen_illegal_regex` —— 按确定性随机源在若干「语法非法类别」间选择，
//     并以安全字面字符（小写字母，永不充当定界符或量词）填充随机内容，
//     从而保证生成的每个字符串都**确定非法**（与 parser.mbt 的文法精确对齐）：
//       0. 未闭合分组      `(aaa`        → Unbalanced("(")
//       1. 未闭合字符类    `[aaa`        → Unbalanced("[")
//       2. 前导悬空量词    `*aa` `+` `?` `{` → DanglingQuantifier
//       3. 多余的右括号    `aaa)`        → TrailingInput
//       4. 末尾悬空转义    `aaa\`        → Unexpected（期望转义字符）
//       5. 原子位置的杂散  `]` / `}`     → Unexpected
//       6. 非法计数量词    `a{}` `a{`    → InvalidRepeat
//   * 「不构造任何自动机」以可观测的流水线建模：仅当 `parse_regex` 成功
//     （`Ok`）才会调用 `build_nfa` / `to_dfa`。对非法输入，解析返回 `Err`，
//     因此被 `Ok` 分支守卫的自动机构造一次都不会发生（构造计数恒为 0）。

// ---------------------------------------------------------------------------
// 非法正则字符串生成器（generator）—— 复用 @infra_pbt 种子驱动随机源
// ---------------------------------------------------------------------------

///|
/// 生成一段由小写字母构成的「安全」内容字符串。
///
/// 字母始终是合法原子，且永不充当定界符（`( ) [ ] { }`）、择一（`|`）、
/// 量词（`* + ? {`）或转义（`\`），因此把它与某个「非法骨架」拼接后，
/// 非法性完全由骨架决定，不会被内容意外「修复」或「再平衡」。
fn gen_safe_letters(
  rng : @infra_pbt.Rng,
  min_len : Int,
  max_len : Int,
) -> String {
  let len = rng.next_range(min_len, max_len)
  let mut s = ""
  let mut i = 0
  while i < len {
    // 'a'..'z' 共 26 个，均为合法字面原子。
    let c = ('a'.to_int() + rng.next_below(26)).unsafe_to_char()
    s = s + "\{c}"
    i = i + 1
  }
  s
}

///|
/// 确定性「语法非法正则字符串」生成器。
///
/// 在 7 个互斥的非法类别间按随机源选择，每个类别都构造出对 parser.mbt 文法
/// 而言**保证非法**的字符串。返回的每个样本都应使 `parse_regex` 返回 `Err`。
fn gen_illegal_regex() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    match rng.next_below(7) {
      // 0. 未闭合分组：'(' 后接字母且无 ')'。
      0 => "(" + gen_safe_letters(rng, 1, 4)
      // 1. 未闭合字符类：'[' 后接字母且无 ']'。
      1 => "[" + gen_safe_letters(rng, 1, 4)
      // 2. 前导悬空量词：量词字符出现在没有可作用对象的串首。
      2 => {
        let quants = ['*', '+', '?', '{']
        let q = quants[rng.next_below(quants.length())]
        "\{q}" + gen_safe_letters(rng, 0, 3)
      }
      // 3. 多余的右括号：字母后接一个无配对的 ')'（顶层残余输入）。
      3 => gen_safe_letters(rng, 0, 4) + ")"
      // 4. 末尾悬空转义：以单个反斜杠结尾，缺少被转义字符。
      4 => gen_safe_letters(rng, 0, 4) + "\\"
      // 5. 原子位置的杂散闭合元字符：']' 或 '}'。
      5 => {
        let stray = if rng.next_bool() { "]" } else { "}" }
        gen_safe_letters(rng, 0, 3) + stray
      }
      // 6. 非法计数量词：原子后接空 / 未闭合的 '{...}'。
      _ => {
        let body = if rng.next_bool() { "{}" } else { "{" }
        gen_safe_letters(rng, 1, 2) + body
      }
    }
  })
}

// ---------------------------------------------------------------------------
// 辅助：把「是否构造了自动机」建模为可观测的流水线
// ---------------------------------------------------------------------------

///|
/// 模拟真实匹配流水线：仅当 `parse_regex` 成功才构造自动机。
///
/// 返回该输入在流水线中触发的自动机构造次数：
///   * `Err` → 0（解析失败，被 `Ok` 分支守卫，不构造任何自动机）；
///   * `Ok`  → 1（解析成功才推进到 Thompson 构造）。
///
/// 对非法输入，本函数恒返回 0，直接对应 R2.3「不构造任何自动机」。
fn automata_built_for(s : String) -> Int {
  match parse_regex(s) {
    Err(_) => 0
    Ok(r) => {
      // 仅在成功路径上构造自动机；非法输入永远不会到达此分支。
      let _nfa = build_nfa(r)
      1
    }
  }
}

// ---------------------------------------------------------------------------
// Property 6：非法表达式错误条件（≥100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 6: Regex 非法表达式错误条件
///
/// 对任意语法非法的正则字符串，`parse_regex` 应：
///   1. 返回 `Err`（解析错误），而非 `Ok`；
///   2. 错误携带落在 `[0, 输入长度]` 内的字符偏移位置（含位置信息）；
///   3. 不构造任何自动机（流水线中自动机构造计数为 0）。
///
/// **Validates: Requirements 2.3**
test "Feature: moonbit-infra-suite, Property 6: illegal regex yields located error and builds no automaton" {
  let ok = @infra_pbt.holds_for_all(gen_illegal_regex(), fn(s) {
    match parse_regex(s) {
      // 本应非法却解析成功 → 性质被违反。
      Ok(_) => false
      Err(e) => {
        let p = e.pos()
        // 错误位置必须含定位且落在合法区间内（ASCII 内容下字符数 == 长度）。
        let located = p >= 0 && p <= s.length()
        // 解析失败 ⇒ 流水线不构造任何自动机。
        let no_automaton = automata_built_for(s) == 0
        located && no_automaton
      }
    }
  })
  assert_true(ok)
}

///|
/// 健全性（sanity）：生成器产出的样本确实全部非法。
///
/// 单独以 100 次迭代校验「每个生成样本都使 parse_regex 返回 Err」，确保
/// 上方主属性不会因生成器漏产合法字符串而被「平凡满足」（vacuously true）。
///
/// **Validates: Requirements 2.3**
test "Feature: moonbit-infra-suite, Property 6: generator only emits illegal strings" {
  let all_illegal = @infra_pbt.holds_for_all(gen_illegal_regex(), fn(s) {
    match parse_regex(s) {
      Err(_) => true
      Ok(_) => false
    }
  })
  assert_true(all_illegal)
}

// ---------------------------------------------------------------------------
// Property 10（旗舰深化）：非法表达式错误条件（`parse_pattern`）
//
// 在既有 Property 6（`parse_regex`）之上扩展：对生成器产出的语法非法模式
// （含重复组名、反向引用、后瞻等不支持构造）校验 `parse_pattern` 返回携带
// 合法字符偏移的解析错误，且不构造任何程序 / 自动机（≥100 迭代）。
//
// **Validates: Requirements 1.7, 2.3**
// ---------------------------------------------------------------------------

///|
/// 确定性「语法非法模式字符串」生成器（面向 `parse_pattern`）。
///
/// 在 10 个互斥非法类别间按随机源选择，每个都对 pattern_parser.mbt 文法保证
/// 非法：既有 7 类结构错误，外加重复组名、反向引用、未闭合后顾三类。
fn gen_illegal_pattern() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    match rng.next_below(10) {
      0 => "(" + gen_safe_letters(rng, 1, 4) // 未闭合分组
      1 => "[" + gen_safe_letters(rng, 1, 4) // 未闭合字符类
      2 => {
        let quants = ['*', '+', '?', '{']
        let q = quants[rng.next_below(quants.length())]
        "\{q}" + gen_safe_letters(rng, 0, 3) // 前导悬空量词
      }
      3 => gen_safe_letters(rng, 0, 4) + ")" // 多余右括号
      4 => gen_safe_letters(rng, 0, 4) + "\\" // 末尾悬空转义
      5 => {
        let stray = if rng.next_bool() { "]" } else { "}" }
        gen_safe_letters(rng, 0, 3) + stray // 杂散闭合元字符
      }
      6 => {
        let body = if rng.next_bool() { "{}" } else { "{" }
        gen_safe_letters(rng, 1, 2) + body // 非法计数量词
      }
      // 旗舰新增：反向引用（不支持）。
      7 => gen_safe_letters(rng, 0, 2) + "\\" + "\{rng.next_range(1, 9)}"
      // 旗舰新增：重复组名。
      8 => {
        let nm = gen_safe_letters(rng, 1, 2)
        "(?<" +
        nm +
        ">" +
        gen_safe_letters(rng, 0, 2) +
        ")(?<" +
        nm +
        ">" +
        gen_safe_letters(rng, 0, 2) +
        ")"
      }
      // 未闭合后顾：缺右括号。
      _ => {
        let kind = if rng.next_bool() { "=" } else { "!" }
        "(?<" + kind + gen_safe_letters(rng, 1, 3)
      }
    }
  })
}

///|
/// 模拟流水线：仅当 `parse_pattern` 成功才编译程序。返回构造的程序数：
///   * `Err` → 0（解析失败，不构造任何程序）；
///   * `Ok`  → 1（解析成功才推进到编译）。
fn programs_built_for(s : String) -> Int {
  match parse_pattern(s) {
    Err(_) => 0
    Ok(a) => {
      let _p = compile_program(a)
      1
    }
  }
}

///|
/// Feature: regex-engine, Property 10: 非法表达式错误条件（parse_pattern）
///
/// 对任意语法非法模式，`parse_pattern` 返回携带合法字符偏移的 `Err`，且不
/// 构造任何程序。
///
/// **Validates: Requirements 1.7, 2.3**
test "Feature: regex-engine, Property 10: illegal pattern yields located error and builds no program" {
  let ok = @infra_pbt.holds_for_all(gen_illegal_pattern(), fn(s) {
    match parse_pattern(s) {
      Ok(_) => false
      Err(e) => {
        let p = e.pos()
        let located = p >= 0 && p <= s.length()
        let no_program = programs_built_for(s) == 0
        located && no_program
      }
    }
  })
  assert_true(ok)
}

///|
/// 健全性：生成器产出的样本确实全部非法（避免主属性被平凡满足）。
///
/// **Validates: Requirements 1.7, 2.3**
test "Feature: regex-engine, Property 10: pattern generator only emits illegal strings" {
  let all_illegal = @infra_pbt.holds_for_all(gen_illegal_pattern(), fn(s) {
    match parse_pattern(s) {
      Err(_) => true
      Ok(_) => false
    }
  })
  assert_true(all_illegal)
}
