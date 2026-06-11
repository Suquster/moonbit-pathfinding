// prop_nfa_dfa_test.mbt —— NFA/DFA 差分一致性属性测试（task 6.4）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 5：「Regex NFA/DFA 差分一致性」——对任意受支持子集内的正则表达式
// 与任意输入字符串，NFA 匹配结果应与 DFA 匹配结果完全一致（是否匹配与匹配
// 区间均相同）。
//
// 两条匹配路径共享 design.md 的同一流水线：
//   syntax → parser → nfa（Thompson 构造）→ dfa（子集构造确定化）→ matcher。
// `Nfa::find` 直接在带 ε 转移的非确定自动机上模拟；`Dfa::find` 在子集构造
// 确定化后的自动机上执行。本属性即断言二者对同一 `(Regex, 输入)` 始终给出
// 逐字段相等的 `Match?` 结果，从而验证确定化变换保持匹配语义（R2.6）。
//
// 输入空间由两个深度受限的随机生成器联合构成（复用 @infra_pbt 的种子驱动
// 随机源 `Rng`，保证三后端逐位一致与可重放）：
//   * `gen_regex_at`    —— 受支持子集内的随机正则语法树生成器；
//   * `gen_input_str`   —— 短随机输入字符串生成器。
// 二者合成 `Gen[(Regex, String)]`，交由 @infra_pbt 的 `holds_for_all` 不变量
// 模板默认迭代 100 次（满足 ≥100 迭代基线）。
//
// 字母表刻意取小且交叠：正则字面 / 字符类多取自 {a,b,c,d,0,1}，输入串亦
// 取自同一小字母表，使匹配 / 不匹配两种情形都被充分覆盖（含字符类范围、
// 否定类与锚点的位置敏感行为）。深度上限保证语法树与自动机规模有界，避免
// 子集构造在 100 次迭代中产生过大的状态空间。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 随机正则语法树生成器（generator）—— 复用 @infra_pbt 种子驱动随机源
// ---------------------------------------------------------------------------

///|
/// 随机字符类（character class）生成器：1~2 个成员项，单字符或小范围，
/// 随机决定是否否定。范围上下界取自小字母表并保证 `lo <= hi`。
fn gen_class(rng : @infra_pbt.Rng) -> Regex {
  let singles : Array[Char] = ['a', 'b', 'c', 'd', '0', '1']
  let negated = rng.next_bool()
  let count = rng.next_range(1, 2)
  let items : Array[ClassItem] = []
  for _i in 0..<count {
    if rng.next_bool() {
      // 单字符成员。
      items.push(Single(singles[rng.next_below(singles.length())]))
    } else {
      // 范围成员 lo-hi（含两端），下界取 'a'..'c'，上界取 [lo, 'e']。
      let lo = rng.next_range('a'.to_int(), 'c'.to_int())
      let hi = rng.next_range(lo, 'e'.to_int())
      items.push(Range(lo.unsafe_to_char(), hi.unsafe_to_char()))
    }
  }
  Class({ negated, items })
}

///|
/// 在给定剩余深度下采样一棵受支持子集内的正则语法树。
///
/// 深度耗尽时收敛为叶子（字面字符 / 字符类 / 锚点）；否则等概率选择各类
/// 节点并递归生成子树。计数量词 `{m,n}` 保证 `n >= m`；串接 / 择一生成
/// 1~3 个子表达式。深度上限保证树规模有界，避免子集构造状态爆炸。
fn gen_regex_at(rng : @infra_pbt.Rng, depth : Int) -> Regex {
  let alphabet : Array[Char] = ['a', 'b', 'c']
  if depth <= 0 {
    // 叶子节点：字面字符、字符类或锚点。
    match rng.next_below(3) {
      0 => Char(alphabet[rng.next_below(alphabet.length())])
      1 => gen_class(rng)
      _ => Anchor(if rng.next_bool() { Start } else { End })
    }
  } else {
    match rng.next_below(9) {
      0 => Char(alphabet[rng.next_below(alphabet.length())])
      1 => gen_class(rng)
      2 => Star(gen_regex_at(rng, depth - 1))
      3 => Plus(gen_regex_at(rng, depth - 1))
      4 => Opt(gen_regex_at(rng, depth - 1))
      5 => {
        // 计数量词：m ∈ [0,2]，随机取无上界 {m,} 或有上界 {m, m+extra}。
        let m = rng.next_below(3)
        if rng.next_bool() {
          Repeat(gen_regex_at(rng, depth - 1), m, None)
        } else {
          let extra = rng.next_below(3)
          Repeat(gen_regex_at(rng, depth - 1), m, Some(m + extra))
        }
      }
      6 => {
        // 串接：1~3 个子表达式。
        let n = rng.next_range(1, 3)
        let parts : Array[Regex] = []
        for _i in 0..<n {
          parts.push(gen_regex_at(rng, depth - 1))
        }
        Concat(parts)
      }
      7 => {
        // 择一：1~3 个分支。
        let n = rng.next_range(1, 3)
        let branches : Array[Regex] = []
        for _i in 0..<n {
          branches.push(gen_regex_at(rng, depth - 1))
        }
        Alt(branches)
      }
      _ => Group(gen_regex_at(rng, depth - 1))
    }
  }
}

///|
/// 随机输入字符串生成器：长度 0~`max_len`，字符取自与正则交叠的小字母表
/// {a,b,c,d,0,1}，以充分覆盖匹配 / 不匹配两种情形。
fn gen_input_str(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let alphabet : Array[Char] = ['a', 'b', 'c', 'd', '0', '1']
  let len = rng.next_below(max_len + 1)
  let mut s = ""
  for _i in 0..<len {
    s = s + "\{alphabet[rng.next_below(alphabet.length())]}"
  }
  s
}

///|
/// 联合生成器：产出 `(随机正则语法树, 随机输入字符串)` 二元组。
///
/// 正则深度上限 3、输入长度上限 6，保证规模有界且匹配情形覆盖充分。
fn gen_regex_and_input() -> @infra_pbt.Gen[(Regex, String)] {
  @infra_pbt.Gen::new(fn(rng) {
    let r = gen_regex_at(rng, 3)
    let s = gen_input_str(rng, 6)
    (r, s)
  })
}

// ---------------------------------------------------------------------------
// 单元测试（具体见证）—— 锁定 NFA/DFA 在代表性样例上的一致性
// ---------------------------------------------------------------------------

///|
/// 对一组代表性 `(正则, 输入)` 样例，NFA 与 DFA 路径给出逐字段相等的结果
/// （Property 5 的具体见证；属性形式见下方 holds_for_all 测试）。
test "nfa and dfa agree on representative witnesses" {
  let cases : Array[(String, String)] = [
    ("a(b|c)*d", "abcbcd"),
    ("[a-c]+", "xaabbz"),
    ("[^0-9]+", "ab12cd"),
    ("^a.*", "a"),
    ("a{2,3}", "aaaa"),
    ("(ab)+", "ababab"),
    ("a*b*", "aaabbb"),
  ]
  for c in cases {
    let (pat, input) = c
    let r = match parse_regex(pat) {
      Ok(rr) => rr
      Err(_) => Char('\u{0}')
    }
    let nfa = build_nfa(r)
    let dfa = to_dfa(nfa)
    assert_true(nfa.find(input) == dfa.find(input))
  }
}

// ---------------------------------------------------------------------------
// Property 5：Regex NFA/DFA 差分一致性
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 5: Regex NFA/DFA 差分一致性
///
/// 对任意由生成器产出的受支持子集正则语法树 `r` 与任意随机输入字符串 `s`，
/// 直接 NFA 模拟（`Nfa::find`）与子集构造确定化后的 DFA 执行（`Dfa::find`）
/// 应给出完全一致的匹配结果——即 `Match?` 的「是否匹配」与「匹配区间
/// （start / end）」逐字段相等。该性质验证确定化变换保持匹配语义（R2.6）。
///
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次
/// （满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 2.6**
test "Feature: moonbit-infra-suite, Property 5: NFA find equals DFA find for all regex and inputs" {
  let ok = @infra_pbt.holds_for_all(gen_regex_and_input(), fn(pair) {
    let (r, s) = pair
    let nfa = build_nfa(r)
    let dfa = to_dfa(nfa)
    nfa.find(s) == dfa.find(s)
  })
  assert_true(ok)
}
