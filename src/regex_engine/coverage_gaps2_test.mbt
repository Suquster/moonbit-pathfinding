// coverage_gaps2_test.mbt —— regex_engine 余支覆盖收口（INFRA 第六十一批）：
// Unicode 子类名全量解析、两代解析器原子位错误分支、未闭合字符类。

///|
test "Unicode 类别：其余子类名全量可解析" {
  let names = [
    "Mc", "Me", "Pi", "Pf", "Sm", "Sc", "Sk", "So", "Zl", "Zp", "Cf", "Co", "Cs",
  ]
  let probes = [
    0x093E, 0x20DD, 0x00AB, 0x00BB, 0x002B, 0x0024, 0x005E, 0x00A9, 0x2028, 0x2029,
    0x200D, 0xE000, 0xD800,
  ]
  for i in 0..<names.length() {
    guard @regex_engine.parse_unicode_class("\\p{" + names[i] + "}") is Some(cs)
    assert_true(cs.contains(probes[i]))
  }
}

///|
test "pattern_parser：原子位元字符与未闭合字符类报错" {
  assert_true(@regex_engine.parse_pattern(")") is Err(_))
  assert_true(@regex_engine.parse_pattern("a)") is Err(_))
  assert_true(@regex_engine.parse_pattern("[") is Err(_))
  assert_true(@regex_engine.parse_pattern("[a") is Err(_))
  assert_true(@regex_engine.parse_pattern("[a\\") is Err(_))
}

///|
test "parser（一代）：原子位元字符与未闭合字符类报错" {
  assert_true(@regex_engine.parse_regex(")") is Err(_))
  assert_true(@regex_engine.parse_regex("a)") is Err(_))
  assert_true(@regex_engine.parse_regex("[") is Err(_))
  assert_true(@regex_engine.parse_regex("[a") is Err(_))
}
