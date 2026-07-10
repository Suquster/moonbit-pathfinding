// unicode_fold_test.mbt —— Unicode 简单大小写折叠完备化（INFRA 第五十六批）。
//
// `case_fold` 自 ASCII 平移升级为 UCD CaseFolding.txt（C+S）轨道闭包：
// 覆盖拉丁补充/扩展、希腊（含词尾 σ）、西里尔、全角字母与多元轨道
// （K↔K、S↔ſ）。

///|
fn uf_prog(s : String) -> Program {
  let f = Flags::default()
  let fi = { ..f, ignore_case: true }
  match parse_pattern(s, flags=fi) {
    Ok(a) => compile_program(a, flags=fi)
    Err(_) => compile_program(Empty)
  }
}

///|
test "Unicode 折叠：拉丁补充与扩展" {
  // é (U+00E9) ↔ É (U+00C9)。
  let p = uf_prog("é")
  assert_true(p.is_match("é"))
  assert_true(p.is_match("É"))
  // ā (U+0101) ↔ Ā (U+0100)（拉丁扩展 A 交替对）。
  let q = uf_prog("Ā")
  assert_true(q.is_match("ā"))
  assert_true(q.is_match("Ā"))
  // × (U+00D7) / ÷ (U+00F7) 非字母：不折叠、不误匹配。
  let r = uf_prog("×")
  assert_true(r.is_match("×"))
  assert_false(r.is_match("÷"))
}

///|
test "Unicode 折叠：希腊与词尾 sigma 三元轨道" {
  // σ (U+03C3) / ς (U+03C2) / Σ (U+03A3) 同一折叠轨道。
  let p = uf_prog("σ")
  assert_true(p.is_match("σ"))
  assert_true(p.is_match("ς"))
  assert_true(p.is_match("Σ"))
  let q = uf_prog("Σ")
  assert_true(q.is_match("ς"))
  // α ↔ Α。
  let r = uf_prog("Α")
  assert_true(r.is_match("α"))
}

///|
test "Unicode 折叠：西里尔与全角字母" {
  // д (U+0434) ↔ Д (U+0414)。
  let p = uf_prog("Д")
  assert_true(p.is_match("д"))
  assert_true(p.is_match("Д"))
  // 全角 Ａ (U+FF21) ↔ ａ (U+FF41)。
  let q = uf_prog("Ａ")
  assert_true(q.is_match("ａ"))
  assert_true(q.is_match("Ａ"))
  assert_false(q.is_match("a")) // 全角与半角不同轨道
}

///|
test "Unicode 折叠：跨区段多元轨道 K/ſ" {
  // KELVIN SIGN U+212A 与 K/k 同轨道。
  let p = uf_prog("k")
  assert_true(p.is_match("K"))
  assert_true(p.is_match("\u{212A}"))
  // LATIN SMALL LETTER LONG S U+017F 与 S/s 同轨道。
  let q = uf_prog("s")
  assert_true(q.is_match("S"))
  assert_true(q.is_match("\u{17F}"))
  let r = uf_prog("\u{17F}")
  assert_true(r.is_match("s"))
  assert_true(r.is_match("S"))
}

///|
test "Unicode 折叠：字符类区间与否定类" {
  // [α-ω] 忽略大小写：匹配大写希腊字母。
  let p = uf_prog("[α-ω]")
  assert_true(p.is_match("Β"))
  assert_true(p.is_match("γ"))
  // 否定类先折叠正类再取补（emit 路径）：[^a] 忽略大小写下 A 也被排除。
  let q = uf_prog("[^ka]")
  assert_false(q.is_match("a"))
  assert_false(q.is_match("k"))
  assert_true(q.is_match("b"))
}
