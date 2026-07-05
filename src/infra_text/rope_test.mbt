// rope_test.mbt —— Rope 黑盒测试：定向（插入/删除/切片/边界）+ 与朴素
// String 重建的差分 PBT + 平衡不变量守卫（对抗性顺序追加）。

///|
/// 朴素参照：整篇重建的字符串编辑。
fn naive_insert(s : String, pos : Int, t : String) -> String {
  let n = s.length()
  let p = if pos < 0 { 0 } else if pos > n { n } else { pos }
  s[0:p].to_owned() + t + s[p:].to_owned()
}

///|
fn naive_delete(s : String, lo : Int, hi : Int) -> String {
  let n = s.length()
  let a = if lo < 0 { 0 } else if lo > n { n } else { lo }
  let b = if hi < a { a } else if hi > n { n } else { hi }
  s[0:a].to_owned() + s[b:].to_owned()
}

///|
test "rope basic: from_string / len / to_string / charcode_at" {
  let r = @infra_text.Rope::from_string("hello, 世界")
  assert_eq(r.len(), 9)
  assert_eq(r.to_string(), "hello, 世界")
  assert_true(r.charcode_at(0) == Some(104)) // 'h'
  assert_true(r.charcode_at(7) == Some(0x4E16)) // '世'
  assert_true(r.charcode_at(9) == None)
  assert_true(r.charcode_at(-1) == None)
  let empty = @infra_text.Rope::new()
  assert_eq(empty.len(), 0)
  assert_eq(empty.to_string(), "")
}

///|
test "rope insert: head / middle / tail / clamped / empty" {
  let r = @infra_text.Rope::from_string("bd")
  r.insert(1, "c")
  assert_eq(r.to_string(), "bcd")
  r.insert(0, "a")
  assert_eq(r.to_string(), "abcd")
  r.insert(4, "e")
  assert_eq(r.to_string(), "abcde")
  r.insert(100, "!") // 越界夹取到尾
  assert_eq(r.to_string(), "abcde!")
  r.insert(-5, "?") // 越界夹取到头
  assert_eq(r.to_string(), "?abcde!")
  r.insert(3, "")
  assert_eq(r.to_string(), "?abcde!")
}

///|
test "rope delete: middle / head / tail / clamped / empty range" {
  let r = @infra_text.Rope::from_string("abcdefg")
  r.delete(2, 4)
  assert_eq(r.to_string(), "abefg")
  r.delete(0, 1)
  assert_eq(r.to_string(), "befg")
  r.delete(3, 100)
  assert_eq(r.to_string(), "bef")
  r.delete(2, 2)
  assert_eq(r.to_string(), "bef")
  r.delete(-3, 1)
  assert_eq(r.to_string(), "ef")
  r.delete(0, 99)
  assert_eq(r.to_string(), "")
  assert_eq(r.len(), 0)
}

///|
test "rope slice: interior / cross-leaf / clamped" {
  // 构造跨多叶文本（> ROPE_LEAF_MAX）。
  let sb = StringBuilder::new()
  for i in 0..<2000 {
    sb.write_char((97 + i % 26).unsafe_to_char())
  }
  let base = sb.to_string()
  let r = @infra_text.Rope::from_string(base)
  assert_eq(r.slice(0, 2000), base)
  assert_eq(r.slice(500, 520), base[500:520].to_owned())
  assert_eq(r.slice(1990, 3000), base[1990:].to_owned())
  assert_eq(r.slice(700, 700), "")
  assert_eq(r.slice(-5, 3), base[0:3].to_owned())
}

///|
test "rope balance invariant under adversarial sequential appends" {
  // 顺序追加是导致朴素 rope 退化为链表的最坏序列。
  let r = @infra_text.Rope::new()
  for i in 0..<3000 {
    r.insert(r.len(), "x\{i % 10}")
  }
  assert_eq(r.len(), 6000)
  assert_true(r.is_leaf_balanced())
  // 头部逐次插入同样保持平衡。
  let r2 = @infra_text.Rope::new()
  for _ in 0..<3000 {
    r2.insert(0, "ab")
  }
  assert_eq(r2.len(), 6000)
  assert_true(r2.is_leaf_balanced())
}

///|
test "rope differential PBT vs naive string rebuild (200 iterations)" {
  let rng = @infra_pbt.rng_new(0xE6_2026_0705UL)
  for _iter in 0..<200 {
    let mut s = ""
    let r = @infra_text.Rope::new()
    let steps = 3 + rng.next_below(30)
    for _step in 0..<steps {
      let n = s.length()
      match rng.next_below(3) {
        0 => {
          // 插入随机短串（含多码元 CJK）。
          let pos = if n == 0 { 0 } else { rng.next_below(n + 1) }
          let sb = StringBuilder::new()
          for _ in 0..<(1 + rng.next_below(8)) {
            match rng.next_below(3) {
              0 => sb.write_char((97 + rng.next_below(26)).unsafe_to_char())
              1 => sb.write_char((0x4E00 + rng.next_below(64)).unsafe_to_char())
              _ => sb.write_char((48 + rng.next_below(10)).unsafe_to_char())
            }
          }
          let t = sb.to_string()
          r.insert(pos, t)
          s = naive_insert(s, pos, t)
        }
        1 =>
          if n > 0 {
            let lo = rng.next_below(n)
            let hi = lo + rng.next_below(n - lo + 1)
            r.delete(lo, hi)
            s = naive_delete(s, lo, hi)
          }
        _ =>
          if n > 0 {
            let lo = rng.next_below(n)
            let hi = lo + rng.next_below(n - lo + 1)
            assert_eq(r.slice(lo, hi), s[lo:hi].to_owned())
          }
      }
      assert_eq(r.len(), s.length())
    }
    assert_eq(r.to_string(), s)
    assert_true(r.is_leaf_balanced())
    // 随机点位码元一致。
    if s.length() > 0 {
      let p = rng.next_below(s.length())
      assert_true(r.charcode_at(p) == Some(s.at(p).to_int()))
    }
  }
}

///|
/// 朴素参照：字符串前缀 [0, upto) 的 UTF-8 字节数（WTF-8 语义）。
fn naive_prefix_u8(s : String, upto : Int) -> Int {
  let mut u8 = 0
  let mut i = 0
  while i < upto {
    let c = s.at(i).to_int()
    if c < 0x80 {
      u8 = u8 + 1
      i = i + 1
    } else if c < 0x800 {
      u8 = u8 + 2
      i = i + 1
    } else if c >= 0xD800 && c < 0xDC00 && i + 1 < upto {
      let d = s.at(i + 1).to_int()
      if d >= 0xDC00 && d < 0xE000 {
        u8 = u8 + 4
        i = i + 2
      } else {
        u8 = u8 + 3
        i = i + 1
      }
    } else {
      u8 = u8 + 3
      i = i + 1
    }
  }
  u8
}

///|
/// 朴素参照：全文扫描求 (行, 列)。
fn naive_line_col(s : String, off : Int) -> (Int, Int) {
  let mut line = 0
  let mut start = 0
  for j in 0..<off {
    if s.at(j).to_int() == 10 {
      line = line + 1
      start = j + 1
    }
  }
  (line, off - start)
}

///|
test "rope editor-grade index: utf8/utf16 conversion & line/col (directed)" {
  // ASCII(1B) + 拉丁扩展 é(2B) + CJK 世(3B) + emoji 😀(4B, 代理对) + 换行。
  let r = @infra_text.Rope::from_string("ab\né世\n😀x")
  assert_eq(r.len(), 9)
  assert_eq(r.utf8_len(), 1 + 1 + 1 + 2 + 3 + 1 + 4 + 1)
  assert_eq(r.line_count(), 3)
  assert_eq(r.utf16_to_utf8(0), 0)
  assert_eq(r.utf16_to_utf8(3), 3) // "ab\n"
  assert_eq(r.utf16_to_utf8(4), 5) // + é
  assert_eq(r.utf16_to_utf8(5), 8) // + 世
  assert_eq(r.utf16_to_utf8(8), 13) // + \n😀
  assert_eq(r.utf16_to_utf8(9), 14)
  // 反向。
  assert_eq(r.utf8_to_utf16(0), 0)
  assert_eq(r.utf8_to_utf16(5), 4)
  assert_eq(r.utf8_to_utf16(8), 5)
  assert_eq(r.utf8_to_utf16(13), 8)
  assert_eq(r.utf8_to_utf16(14), 9)
  // 落在字符中间向下取整。
  assert_eq(r.utf8_to_utf16(4), 3)
  assert_eq(r.utf8_to_utf16(10), 6)
  // 行列。
  assert_eq(r.offset_of_line(0), 0)
  assert_eq(r.offset_of_line(1), 3)
  assert_eq(r.offset_of_line(2), 6)
  assert_true(r.line_col_at(0) == (0, 0))
  assert_true(r.line_col_at(2) == (0, 2))
  assert_true(r.line_col_at(4) == (1, 1))
  assert_true(r.line_col_at(8) == (2, 2))
}

///|
test "rope index differential PBT vs naive full scan after edits (200 iterations)" {
  let rng = @infra_pbt.rng_new(0xE6_1D_2026UL)
  for _iter in 0..<200 {
    let mut s = ""
    let r = @infra_text.Rope::new()
    // 随机编辑若干步（字符边界对齐的插入，含换行/2B/3B/4B 字符）。
    for _step in 0..<(3 + rng.next_below(12)) {
      let n = s.length()
      if n > 0 && rng.next_below(4) == 0 {
        // 删除（对齐字符边界：避开代理对中缝）。
        let mut lo = rng.next_below(n)
        if s.at(lo).to_int() >= 0xDC00 && s.at(lo).to_int() < 0xE000 {
          lo = lo - 1
        }
        let mut hi = lo + rng.next_below(n - lo + 1)
        if hi < n && s.at(hi).to_int() >= 0xDC00 && s.at(hi).to_int() < 0xE000 {
          hi = hi + 1
        }
        r.delete(lo, hi)
        s = naive_delete(s, lo, hi)
      } else {
        let mut pos = if n == 0 { 0 } else { rng.next_below(n + 1) }
        if pos < n &&
          s.at(pos).to_int() >= 0xDC00 &&
          s.at(pos).to_int() < 0xE000 {
          pos = pos + 1
        }
        let sb = StringBuilder::new()
        for _ in 0..<(1 + rng.next_below(10)) {
          match rng.next_below(5) {
            0 => sb.write_char('\n')
            1 => sb.write_char((0xE9).unsafe_to_char()) // é 2B
            2 => sb.write_char((0x4E00 + rng.next_below(32)).unsafe_to_char()) // 3B
            3 => sb.write_char((0x1F600 + rng.next_below(16)).unsafe_to_char()) // 4B 代理对
            _ => sb.write_char((97 + rng.next_below(26)).unsafe_to_char())
          }
        }
        let t = sb.to_string()
        r.insert(pos, t)
        s = naive_insert(s, pos, t)
      }
    }
    assert_eq(r.to_string(), s)
    assert_eq(r.utf8_len(), naive_prefix_u8(s, s.length()))
    // 随机字符边界偏移双向转换 + 行列 vs 朴素全扫描。
    for _q in 0..<8 {
      let mut off = rng.next_below(s.length() + 1)
      if off < s.length() &&
        s.at(off).to_int() >= 0xDC00 &&
        s.at(off).to_int() < 0xE000 {
        off = off + 1
      }
      let u8off = naive_prefix_u8(s, off)
      assert_eq(r.utf16_to_utf8(off), u8off)
      assert_eq(r.utf8_to_utf16(u8off), off)
      let (line, col) = naive_line_col(s, off)
      assert_true(r.line_col_at(off) == (line, col))
    }
    // 每行行首偏移与朴素一致。
    let mut expect = 0
    let mut line_no = 0
    assert_eq(r.offset_of_line(0), 0)
    for j in 0..<s.length() {
      if s.at(j).to_int() == 10 {
        line_no = line_no + 1
        expect = j + 1
        assert_eq(r.offset_of_line(line_no), expect)
      }
    }
    assert_eq(r.line_count(), line_no + 1)
  }
}

///|
test "rope million-char scale: random edits stay balanced & consistent" {
  // 百万码元文档 + 512 次随机编辑：平衡不变量 + 抽样切片一致性。
  let sb = StringBuilder::new()
  for i in 0..<1_000_000 {
    sb.write_char((97 + i % 26).unsafe_to_char())
  }
  let r = @infra_text.Rope::from_string(sb.to_string())
  assert_eq(r.len(), 1_000_000)
  let rng = @infra_pbt.rng_new(0xB16_D0CUL)
  for _ in 0..<512 {
    let n = r.len()
    if rng.next_bool() {
      r.insert(rng.next_below(n + 1), "INSERT")
    } else {
      let lo = rng.next_below(n)
      let hi = lo + rng.next_below(16)
      r.delete(lo, hi)
    }
    assert_true(r.is_leaf_balanced())
  }
  // 物化后长度与逐点抽样一致。
  let final_s = r.to_string()
  assert_eq(final_s.length(), r.len())
  let mut i = 0
  while i < r.len() {
    assert_true(r.charcode_at(i) == Some(final_s.at(i).to_int()))
    i = i + 97_003
  }
}
