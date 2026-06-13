// prop_greedy_lazy_test.mbt —— Property 4：贪婪 / 惰性单调性（任务 6.3）。
//
// Feature: regex-engine, Property 4: 贪婪 / 惰性单调性
//
// 对任意含量词正则，将其顶层量词取贪婪与取惰性两个变体分别匹配同一输入，
// 贪婪变体所得整体匹配区间长度恒不小于同位置惰性变体所得整体匹配区间长度。
//
// **Validates: Requirements 3.2, 3.3, 3.5**
//
// 在 `LeftmostFirst`（PCRE/Perl）策略下区分贪婪 / 惰性最显著：贪婪尽可能多匹配、
// 惰性尽可能少匹配；二者语言相同（同时匹配或同时不匹配），且最左起点相同，
// 故贪婪 end 不早于惰性 end。复用 @infra_pbt 种子驱动随机源（≥100 迭代）。

///|
/// 量词作用对象（原子）：单字符 / 字符类（取自与输入交叠的小字母表）。
fn gl_operand(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(5) {
    0 => "a"
    1 => "b"
    2 => "c"
    3 => "[ab]"
    _ => "(abc)"
  }
}

///|
/// 量词后缀（贪婪形态）：`*` / `+` / `?` / `{m,n}` / `{m,}`。
fn gl_quant(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(5) {
    0 => "*"
    1 => "+"
    2 => "?"
    3 => {
      let m = rng.next_below(3)
      let n = m + rng.next_range(1, 2)
      "{" + m.to_string() + "," + n.to_string() + "}"
    }
    _ => {
      let m = rng.next_range(1, 2)
      "{" + m.to_string() + ",}"
    }
  }
}

///|
/// 输入生成器：字符取自 {a,b,c}，长度 0~`max_len`。
fn gl_input(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let alphabet : Array[Char] = ['a', 'b', 'c']
  let len = rng.next_below(max_len + 1)
  let mut s = ""
  for _i in 0..<len {
    s = s + alphabet[rng.next_below(alphabet.length())].to_string()
  }
  s
}

///|
/// 联合生成器：`(量词作用对象, 量词后缀, 输入)`。
fn gen_greedy_lazy_case() -> @infra_pbt.Gen[(String, String, String)] {
  @infra_pbt.Gen::new(fn(rng) {
    (gl_operand(rng), gl_quant(rng), gl_input(rng, 6))
  })
}

///|
/// 取整体匹配长度（无匹配返回 `None`）。
fn gl_match_len(pat : String, input : String) -> Int? {
  match Pattern::compile(pat, kind=LeftmostFirst) {
    Err(_) => None
    Ok(p) =>
      match p.find(input) {
        Some(m) => Some(m.end - m.start)
        None => None
      }
  }
}

///|
/// Feature: regex-engine, Property 4: 贪婪 / 惰性单调性
///
/// **Validates: Requirements 3.2, 3.3, 3.5**
test "Feature: regex-engine, Property 4: greedy/lazy length monotonicity" {
  let ok = @infra_pbt.holds_for_all(gen_greedy_lazy_case(), fn(triple) {
    let (operand, quant, input) = triple
    let greedy_pat = operand + quant
    let lazy_pat = operand + quant + "?"
    match (gl_match_len(greedy_pat, input), gl_match_len(lazy_pat, input)) {
      // 语言相同：同时匹配。贪婪长度 ≥ 惰性长度。
      (Some(gl), Some(lz)) => gl >= lz
      // 同时无匹配：性质平凡成立。
      (None, None) => true
      // 仅一侧匹配：贪婪 / 惰性语言相同，不应发生；视为违反。
      _ => false
    }
  })
  assert_true(ok)
}

///|
/// 代表性见证：贪婪 `a+` 取最长、惰性 `a+?` 取最短（LeftmostFirst）。
test "greedy/lazy representative witnesses" {
  match
    (
      Pattern::compile("a+", kind=LeftmostFirst),
      Pattern::compile("a+?", kind=LeftmostFirst),
    ) {
    (Ok(g), Ok(l)) => {
      assert_true(g.find("aaa") == Some({ start: 0, end: 3 }))
      assert_true(l.find("aaa") == Some({ start: 0, end: 1 }))
    }
    _ => fail("compile failed for a+ / a+?")
  }
  // `a*` 贪婪取全部前导 'a'，`a*?` 惰性取空。
  match
    (
      Pattern::compile("a*", kind=LeftmostFirst),
      Pattern::compile("a*?", kind=LeftmostFirst),
    ) {
    (Ok(g), Ok(l)) => {
      assert_true(g.find("aab") == Some({ start: 0, end: 2 }))
      assert_true(l.find("aab") == Some({ start: 0, end: 0 }))
    }
    _ => fail("compile failed for a* / a*?")
  }
}
