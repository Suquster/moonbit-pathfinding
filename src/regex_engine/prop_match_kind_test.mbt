// prop_match_kind_test.mbt —— Property 5：匹配策略序关系不变量（任务 6.4）。
//
// Feature: regex-engine, Property 5: 匹配策略序关系不变量
//
// 对任意正则与任意输入，`LeftmostLongest`（POSIX）所得整体匹配区间的起点不
// 晚于 `LeftmostFirst`（PCRE/Perl）所得起点，且长度不小于后者长度。
//
// **Validates: Requirements 2.3, 4.3, 4.4, 4.5**
//
// 两策略只改变「同起点多候选」时的取舍、不改变可匹配性，故对同一模式同时
// 匹配或同时不匹配，且最左起点相同（`<=` 成立），LL 取最长（长度 `>=` 成立）。
//
// 本文件并定义**共享合法模式生成器** `gen_valid_pattern` / `gvp_input` /
// `gen_pat_input`，供 Property 7（find_all）与 Property 8（split/replace）复用：
// 结构化构造保证产出的模式串恒被 `parse_pattern` 接受（无命名组，避免重名）。

// ---------------------------------------------------------------------------
// 共享合法模式生成器（structurally valid pattern generator）
// ---------------------------------------------------------------------------

///|
/// 原子：字面字符 / 字符类 / 点号（取自与输入交叠的小字母表）。
fn gvp_atom(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(6) {
    0 => "a"
    1 => "b"
    2 => "c"
    3 => "[abc]"
    4 => "[a-c]"
    _ => "."
  }
}

///|
/// 原子或分组：深度 > 0 时以一定概率产出捕获 / 非捕获分组（递归），否则原子。
fn gvp_atom_or_group(rng : @infra_pbt.Rng, depth : Int) -> String {
  if depth <= 0 {
    gvp_atom(rng)
  } else {
    match rng.next_below(6) {
      3 => "(" + gvp_expr(rng, depth - 1) + ")"
      4 => "(?:" + gvp_expr(rng, depth - 1) + ")"
      _ => gvp_atom(rng)
    }
  }
}

///|
/// 惰性后缀：约 1/3 概率追加 `?`（仅在已有量词后调用，保证合法）。
fn gvp_lazy(rng : @infra_pbt.Rng) -> String {
  if rng.next_below(3) == 0 {
    "?"
  } else {
    ""
  }
}

///|
/// 一个 piece：原子 / 分组 + 至多一个量词（`*` `+` `?` `{m,n}`，可带惰性 `?`）。
fn gvp_piece(rng : @infra_pbt.Rng, depth : Int) -> String {
  let base = gvp_atom_or_group(rng, depth)
  match rng.next_below(6) {
    1 => base + "*" + gvp_lazy(rng)
    2 => base + "+" + gvp_lazy(rng)
    3 => base + "?" + gvp_lazy(rng)
    4 => {
      let m = rng.next_below(3)
      let n = m + rng.next_range(0, 2)
      base + "{" + m.to_string() + "," + n.to_string() + "}" + gvp_lazy(rng)
    }
    _ => base // 无量词
  }
}

///|
/// 串接：1~3 个 piece 顺序拼接（每个 piece 非空、不以量词字符起始）。
fn gvp_concat(rng : @infra_pbt.Rng, depth : Int) -> String {
  let n = rng.next_range(1, 3)
  let mut s = ""
  for _i in 0..<n {
    s = s + gvp_piece(rng, depth)
  }
  s
}

///|
/// 表达式：约 1/4 概率为两路择一 `c1|c2`，否则单个串接。
fn gvp_expr(rng : @infra_pbt.Rng, depth : Int) -> String {
  if depth > 0 && rng.next_below(4) == 0 {
    gvp_concat(rng, depth - 1) + "|" + gvp_concat(rng, depth - 1)
  } else {
    gvp_concat(rng, depth)
  }
}

///|
/// 共享合法模式生成器：深度上限 3，恒产出 `parse_pattern` 接受的模式串。
fn gen_valid_pattern() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) { gvp_expr(rng, 3) })
}

///|
/// 共享输入生成器：字符取自 {a,b,c}，长度 0~`max_len`。
fn gvp_input(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let alphabet : Array[Char] = ['a', 'b', 'c']
  let len = rng.next_below(max_len + 1)
  let mut s = ""
  for _i in 0..<len {
    s = s + alphabet[rng.next_below(alphabet.length())].to_string()
  }
  s
}

///|
/// 共享联合生成器：`(合法模式, 随机输入)`。
fn gen_pat_input() -> @infra_pbt.Gen[(String, String)] {
  @infra_pbt.Gen::new(fn(rng) { (gvp_expr(rng, 3), gvp_input(rng, 6)) })
}

// ---------------------------------------------------------------------------
// 健全性 + Property 5
// ---------------------------------------------------------------------------

///|
/// 健全性：共享生成器只产出可成功编译的模式（保护下游 Property 5/7/8）。
test "shared valid pattern generator only emits compilable patterns" {
  let ok = @infra_pbt.holds_for_all(gen_valid_pattern(), fn(pat) {
    match Pattern::compile(pat) {
      Ok(_) => true
      Err(_) => false
    }
  })
  assert_true(ok)
}

///|
/// Feature: regex-engine, Property 5: 匹配策略序关系不变量
///
/// **Validates: Requirements 2.3, 4.3, 4.4, 4.5**
test "Feature: regex-engine, Property 5: match kind ordering invariant" {
  let ok = @infra_pbt.holds_for_all(gen_pat_input(), fn(pair) {
    let (pat, input) = pair
    match
      (
        Pattern::compile(pat, kind=LeftmostLongest),
        Pattern::compile(pat, kind=LeftmostFirst),
      ) {
      (Ok(pll), Ok(plf)) =>
        match (pll.find(input), plf.find(input)) {
          (Some(ll), Some(lf)) =>
            ll.start <= lf.start && ll.end - ll.start >= lf.end - lf.start
          (None, None) => true // 同语言：同时无匹配。
          _ => false // 仅一侧匹配不应发生。
        }
      _ => false
    }
  })
  assert_true(ok)
}

///|
/// 代表性见证：`a|ab` 在 "ab" 上，LL 取最长 [0,2)、LF 取首分支 [0,1)。
test "match kind ordering representative witnesses" {
  match
    (
      Pattern::compile("a|ab", kind=LeftmostLongest),
      Pattern::compile("a|ab", kind=LeftmostFirst),
    ) {
    (Ok(pll), Ok(plf)) => {
      assert_true(pll.find("ab") == Some({ start: 0, end: 2 }))
      assert_true(plf.find("ab") == Some({ start: 0, end: 1 }))
    }
    _ => fail("compile failed for a|ab")
  }
}
