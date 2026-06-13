// flags_charset_test.mbt —— `flags` / `charset_ext` 单元测试（任务 1.5）。
//
// 覆盖 `Flags::parse` 边界、预定义类成员判定、`union`/`complement`/`case_fold`
// 的代表样例与空集 / 全集边界（R6.1/6.4/6.7）。

///|
/// `Flags::parse` 解析 `i`/`m`/`s` 子集，未识别字符忽略。
test "Flags::parse parses ims subset and ignores unknown" {
  let d = Flags::default()
  assert_false(d.ignore_case)
  assert_false(d.multiline)
  assert_false(d.dotall)
  let all = Flags::parse("ims")
  assert_true(all.ignore_case && all.multiline && all.dotall)
  let only_i = Flags::parse("i")
  assert_true(only_i.ignore_case)
  assert_false(only_i.multiline)
  // 未识别字符（x/y/z）忽略，仅 m 生效。
  let m = Flags::parse("xyzm")
  assert_true(m.multiline)
  assert_false(m.ignore_case)
  assert_false(m.dotall)
}

///|
/// 预定义字符类成员判定符合 ASCII 约定。
test "predefined classes membership" {
  let digit = predef_digit()
  assert_true(digit.contains('0'.to_int()))
  assert_true(digit.contains('9'.to_int()))
  assert_false(digit.contains('a'.to_int()))
  let word = predef_word()
  assert_true(word.contains('_'.to_int()))
  assert_true(word.contains('Z'.to_int()))
  assert_true(word.contains('5'.to_int()))
  assert_false(word.contains('-'.to_int()))
  let space = predef_space()
  assert_true(space.contains(' '.to_int()))
  assert_true(space.contains('\t'.to_int()))
  assert_true(space.contains('\n'.to_int()))
  assert_false(space.contains('x'.to_int()))
}

///|
/// `\D`/`\W`/`\S` 恰为对应正向类的补集。
test "negated predefined classes are exact complements" {
  let nd = predef_non_digit()
  assert_false(nd.contains('3'.to_int()))
  assert_true(nd.contains('a'.to_int()))
  let nw = predef_non_word()
  assert_false(nw.contains('a'.to_int()))
  assert_true(nw.contains('-'.to_int()))
  let ns = predef_non_space()
  assert_false(ns.contains(' '.to_int()))
  assert_true(ns.contains('x'.to_int()))
}

///|
/// `CharSet::union` 合并相邻 / 相离区间并归一化。
test "CharSet::union merges adjacent and disjoint intervals" {
  let a : CharSet = { intervals: [(1, 3)] }
  let b : CharSet = { intervals: [(4, 6)] }
  // 相邻 (3 与 4) 合并为 (1,6)。
  assert_true(a.union(b) == ({ intervals: [(1, 6)] } : CharSet))
  let c : CharSet = { intervals: [(10, 12)] }
  // 相离保持两段。
  assert_true(a.union(c) == ({ intervals: [(1, 3), (10, 12)] } : CharSet))
}

///|
/// `CharSet::complement` 在 [0, MAX_CODE] 上取补，空集 / 全集互为补集。
test "CharSet::complement on empty and full sets" {
  // MAX_CODE = U+10FFFF（与 nfa.mbt 的码点上界一致）。
  let max_code = 0x10FFFF
  let empty : CharSet = { intervals: [] }
  assert_true(empty.complement() == ({ intervals: [(0, max_code)] } : CharSet))
  let full : CharSet = { intervals: [(0, max_code)] }
  assert_true(full.complement() == ({ intervals: [] } : CharSet))
}

///|
/// `CharSet::case_fold` 对 ASCII 字母取大小写闭包，非字母不变。
test "CharSet::case_fold ascii closure" {
  let upper : CharSet = { intervals: [('A'.to_int(), 'A'.to_int())] }
  let folded = upper.case_fold()
  assert_true(folded.contains('A'.to_int()))
  assert_true(folded.contains('a'.to_int()))
  let lower : CharSet = { intervals: [('z'.to_int(), 'z'.to_int())] }
  let f2 = lower.case_fold()
  assert_true(f2.contains('Z'.to_int()))
  assert_true(f2.contains('z'.to_int()))
  // 数字不受影响。
  let digit : CharSet = { intervals: [('5'.to_int(), '5'.to_int())] }
  assert_true(digit.case_fold() == digit)
}
