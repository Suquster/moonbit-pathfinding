// text_builder_test.mbt —— `TextBuilder` 的最小示例（example-based）单元测试。
//
// 注：跨随机输入的属性测试（往返/等价/再追加保持/线性）由任务 1.2 的
// 属性测试承载，此处仅以少量固定示例守护核心不变量，避免与 1.2 重复。

///|
/// 示例：空构建器物化为空串，且 `is_empty` / `len` 正确。
test "TextBuilder 空构建器" {
  let tb = TextBuilder::new()
  assert_true(tb.is_empty())
  assert_eq(tb.len(), 0)
  assert_eq(tb.build(), "")
}

///|
/// 示例：混合 `push_char` 与 `push_str`，物化结果与等价顺序拼接逐字符相等。
test "TextBuilder 混合追加等价于顺序拼接" {
  let tb = TextBuilder::new()
  tb.push_str("ab")
  tb.push_char('c')
  tb.push_char('d')
  tb.push_str("ef")
  let expected = "ab" + "c".to_string() + "d".to_string() + "ef"
  assert_eq(tb.build(), expected)
  assert_eq(tb.build(), "abcdef")
  assert_eq(tb.len(), 6)
  assert_true(!tb.is_empty())
}

///|
/// 示例（AC4）：`build` 后继续追加，再次 `build` 含全部历史片段且顺序保持。
test "TextBuilder build 后再追加保持全部历史片段" {
  let tb = TextBuilder::new()
  tb.push_str("hello")
  let first = tb.build()
  assert_eq(first, "hello")
  tb.push_char(' ')
  tb.push_str("world")
  assert_eq(tb.build(), "hello world")
  assert_eq(tb.len(), 11)
}

///|
/// 示例：`reset` 后构建器回到全新空状态。
test "TextBuilder reset 清空状态" {
  let tb = TextBuilder::with_capacity(4)
  tb.push_str("abc")
  tb.push_char('d')
  assert_eq(tb.build(), "abcd")
  tb.reset()
  assert_true(tb.is_empty())
  assert_eq(tb.len(), 0)
  assert_eq(tb.build(), "")
  tb.push_str("xyz")
  assert_eq(tb.build(), "xyz")
}

///|
/// 示例：空串 `push_str` 不改变长度也不影响字符缓冲的顺序语义。
test "TextBuilder 空串追加不破坏顺序" {
  let tb = TextBuilder::new()
  tb.push_char('a')
  tb.push_str("")
  tb.push_char('b')
  assert_eq(tb.build(), "ab")
  assert_eq(tb.len(), 2)
}
