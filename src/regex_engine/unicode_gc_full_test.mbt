// unicode_gc_full_test.mbt —— UCD 全量 General_Category 表核验
// （INFRA 第六十批）：新增类别（M/S 大类、Pi/Pf/Zl/Zp/Cf/Co/Cs）、
// 跨平面码点、Cn 补集与分类唯一性。

///|
test "unicode_gc 全表：新增子类查表" {
  // Mn：组合尖音符；Mc：Devanagari 元音符号 AA；Me：组合包围圈。
  assert_true(@regex_engine.unicode_category(0x0301) is Mn)
  assert_true(@regex_engine.unicode_category(0x093E) is Mc)
  assert_true(@regex_engine.unicode_category(0x20DD) is Me)
  // Sm/Sc/Sk/So：加号、欧元、扬抑符、版权符。
  assert_true(@regex_engine.unicode_category('+'.to_int()) is Sm)
  assert_true(@regex_engine.unicode_category(0x20AC) is Sc)
  assert_true(@regex_engine.unicode_category(0x02C2) is Sk)
  assert_true(@regex_engine.unicode_category(0x00A9) is So)
  // Pi/Pf：«»；Zl/Zp：行/段分隔符。
  assert_true(@regex_engine.unicode_category(0x00AB) is Pi)
  assert_true(@regex_engine.unicode_category(0x00BB) is Pf)
  assert_true(@regex_engine.unicode_category(0x2028) is Zl)
  assert_true(@regex_engine.unicode_category(0x2029) is Zp)
  // Cf/Co/Cs：零宽连接符、私用区、代理区。
  assert_true(@regex_engine.unicode_category(0x200D) is Cf)
  assert_true(@regex_engine.unicode_category(0xE000) is Co)
  assert_true(@regex_engine.unicode_category(0xD800) is Cs)
}

///|
test "unicode_gc 全表：跨平面码点" {
  // 补充平面：数学花体大写（Lu）、音乐符号（So）、CJK 扩展 B（Lo）、
  // 平面 16 私用区（Co）。
  assert_true(@regex_engine.unicode_category(0x1D4D0) is Lu)
  assert_true(@regex_engine.unicode_category(0x1D11E) is So)
  assert_true(@regex_engine.unicode_category(0x20000) is Lo)
  assert_true(@regex_engine.unicode_category(0x100000) is Co)
  // 平面尾未分配。
  assert_true(@regex_engine.unicode_category(0x2FFFE) is Cn)
}

///|
test "unicode_gc 全表：大类 M/S 与 C（含 Cn）解析" {
  guard @regex_engine.parse_unicode_class("\\p{M}") is Some(m)
  assert_true(m.contains(0x0301) && m.contains(0x093E) && m.contains(0x20DD))
  assert_false(m.contains('a'.to_int()))
  guard @regex_engine.parse_unicode_class("\\p{S}") is Some(s)
  assert_true(s.contains('+'.to_int()) && s.contains(0x20AC))
  assert_false(s.contains('!'.to_int()))
  guard @regex_engine.parse_unicode_class("\\p{C}") is Some(c)
  assert_true(c.contains(0x00) && c.contains(0x200D) && c.contains(0x0378))
  guard @regex_engine.parse_unicode_class("\\p{Cn}") is Some(cn)
  assert_true(cn.contains(0x0378))
  assert_false(cn.contains('a'.to_int()))
}

///|
test "unicode_gc 全表：分类唯一且大类并集互补" {
  // 任意码点恰属一个类别：所属类别的 CharSet 含之，任一其他大类不含。
  let probes = [0x41, 0x0301, 0x0660, 0x20AC, 0x2028, 0xD800, 0x0378, 0x20000]
  for cp in probes {
    let gc = @regex_engine.unicode_category(cp)
    assert_true(@regex_engine.category_charset(gc).contains(cp))
  }
  // 七大类并集 = 全域（对若干探针码点必属其一）。
  let names = ["L", "M", "N", "P", "S", "Z", "C"]
  for cp in probes {
    let mut hits = 0
    for nm in names {
      guard @regex_engine.parse_unicode_class("\\p{" + nm + "}") is Some(cs)
      if cs.contains(cp) {
        hits = hits + 1
      }
    }
    assert_eq(hits, 1)
  }
}

///|
test "unicode_gc 全表：\\p 类别正则实战" {
  // \p{Sc}+ 匹配货币符号串；\p{M} 匹配组合记号。
  guard @regex_engine.parse_pattern("\\p{Sc}+") is Ok(ast)
  let prog = @regex_engine.compile_program(ast)
  match prog.exec("x€$¥z") {
    Some(c) =>
      match c.group(0) {
        Some(m) => assert_true(m.start == 1 && m.end == 4)
        None => fail("整体匹配区间缺失")
      }
    None => fail("\\p{Sc}+ 应命中 €$¥")
  }
  guard @regex_engine.parse_pattern("a\\p{Mn}") is Ok(ast2)
  let prog2 = @regex_engine.compile_program(ast2)
  assert_true(prog2.exec("a\u{0301}") is Some(_))
}
