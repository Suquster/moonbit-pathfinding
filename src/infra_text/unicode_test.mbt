// unicode_test.mbt —— Unicode 分析原语（宽度 / 字素簇 / 折叠）测试。

///|
test "display width follows wcwidth semantics" {
  assert_eq(@infra_text.display_width(""), 0)
  assert_eq(@infra_text.display_width("hello"), 5)
  // CJK 每字 2 列。
  assert_eq(@infra_text.display_width("路径规划"), 8)
  // 混合：ASCII 1 列 + CJK 2 列。
  assert_eq(@infra_text.display_width("a水b"), 4)
  // 全角形式 2 列。
  assert_eq(@infra_text.display_width("ＡＢ"), 4)
  // 组合标记 0 列：e + U+0301。
  assert_eq(@infra_text.display_width("e\u{0301}"), 1)
  // 控制字符 0 列。
  assert_eq(@infra_text.display_width("\t\u{0007}"), 0)
  // emoji 2 列。
  assert_eq(@infra_text.display_width("\u{1F600}"), 2)
  // 谚文音节 2 列。
  assert_eq(@infra_text.display_width("한글"), 4)
}

///|
test "grapheme clusters follow uax29 subset" {
  // 纯 ASCII：逐字符。
  assert_true(@infra_text.grapheme_clusters("abc") == ["a", "b", "c"])
  // GB3：CR LF 一簇。
  assert_eq(@infra_text.grapheme_count("a\r\nb"), 3)
  // 组合标记并入前簇：e + U+0301 是 1 簇。
  assert_eq(@infra_text.grapheme_count("e\u{0301}"), 1)
  // 肤色修饰符并入前簇：👍 + 肤色。
  assert_eq(@infra_text.grapheme_count("\u{1F44D}\u{1F3FB}"), 1)
  // GB11：ZWJ emoji 序列（👨‍👩‍👧 = 5 码点）是 1 簇。
  assert_eq(
    @infra_text.grapheme_count("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"),
    1,
  )
  // GB12：两个 Regional Indicator（🇨🇳）是 1 簇；四个是 2 簇。
  assert_eq(@infra_text.grapheme_count("\u{1F1E8}\u{1F1F3}"), 1)
  assert_eq(
    @infra_text.grapheme_count("\u{1F1E8}\u{1F1F3}\u{1F1FA}\u{1F1F8}"),
    2,
  )
  // 变体选择符并入前簇。
  assert_eq(@infra_text.grapheme_count("\u{2764}\u{FE0F}"), 1)
  // 簇拼接还原原串。
  let s = "路e\u{0301}\r\n\u{1F1E8}\u{1F1F3}x"
  let mut joined = ""
  for g in @infra_text.grapheme_clusters(s) {
    joined = joined + g
  }
  assert_eq(joined, s)
}

///|
test "case fold covers ascii latin1 greek cyrillic" {
  assert_eq(@infra_text.case_fold("Hello WORLD"), "hello world")
  assert_eq(@infra_text.case_fold("ÀÉÎÕÜ"), "àéîõü")
  // 乘号 × (U+00D7) 不折叠。
  assert_eq(@infra_text.case_fold("×"), "×")
  assert_eq(@infra_text.case_fold("ΑΒΓΔΩ"), "αβγδω")
  assert_eq(@infra_text.case_fold("МОСКВА"), "москва")
  assert_eq(@infra_text.case_fold("Ѐ"), "ѐ")
  // 范围之外原样保留（CJK 无大小写）。
  assert_eq(@infra_text.case_fold("路径"), "路径")
  assert_true(@infra_text.eq_fold("PathFinding", "pathfinding"))
  assert_true(@infra_text.eq_fold("ΣΟΦΙΑ", "σοφια"))
  assert_true(!@infra_text.eq_fold("abc", "abd"))
}

///|
test "case fold is idempotent (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  for _ in 0..<100 {
    let sb = StringBuilder::new()
    for _ in 0..<rng.next_below(16) {
      // 覆盖折叠范围内外的码点。
      let cp = match rng.next_below(5) {
        0 => 0x41 + rng.next_below(26) // A-Z
        1 => 0x61 + rng.next_below(26) // a-z
        2 => 0x391 + rng.next_below(24) // 希腊大写
        3 => 0x410 + rng.next_below(32) // 西里尔大写
        _ => 0x4E00 + rng.next_below(100) // CJK
      }
      match cp.to_char() {
        Some(c) => sb.write_char(c)
        None => ()
      }
    }
    let s = sb.to_string()
    let once = @infra_text.case_fold(s)
    assert_eq(@infra_text.case_fold(once), once)
    // 折叠不改变码点数。
    assert_eq(once.iter().to_array().length(), s.iter().to_array().length())
  }
}

///|
test "grapheme clusters concatenation invariant (pbt)" {
  let rng = @infra_pbt.rng_new(42UL)
  for _ in 0..<100 {
    let sb = StringBuilder::new()
    for _ in 0..<rng.next_below(12) {
      let cp = match rng.next_below(6) {
        0 => 0x61 + rng.next_below(26)
        1 => 0x4E00 + rng.next_below(50)
        2 => 0x0301 // 组合标记
        3 => 0x200D // ZWJ
        4 => 0x1F1E6 + rng.next_below(26) // Regional Indicator
        _ => 0x1F600 + rng.next_below(16) // emoji
      }
      match cp.to_char() {
        Some(c) => sb.write_char(c)
        None => ()
      }
    }
    let s = sb.to_string()
    // 不变量 1：簇拼接还原原串。
    let mut joined = ""
    for g in @infra_text.grapheme_clusters(s) {
      joined = joined + g
    }
    assert_eq(joined, s)
    // 不变量 2：簇数不超过码点数。
    assert_true(@infra_text.grapheme_count(s) <= s.iter().to_array().length())
  }
}
