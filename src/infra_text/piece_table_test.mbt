// piece_table_test.mbt —— PieceTable 黑盒测试：定向（分裂/删除/边界）+
// 与朴素 String 参照差分 PBT + 与 Rope 交叉差分。

///|
test "piece table basic: insert splits, delete shrinks, char_at" {
  let pt = @infra_text.PieceTable::from_string("hello world")
  assert_eq(pt.len(), 11)
  assert_eq(pt.piece_count(), 1)
  // 中间插入 → 一分为三。
  pt.insert(5, ",")
  assert_eq(pt.to_string(), "hello, world")
  assert_eq(pt.piece_count(), 3)
  // 头/尾插入。
  pt.insert(0, ">>")
  pt.insert(pt.len(), "<<")
  assert_eq(pt.to_string(), ">>hello, world<<")
  // 跨 piece 删除。
  pt.delete(2, 6) // 删 "hello,"
  assert_eq(pt.to_string(), ">> world<<")
  assert_true(pt.code_unit_at(0) == Some('>'.to_int()))
  assert_true(pt.code_unit_at(3) == Some('w'.to_int()))
  assert_true(pt.code_unit_at(pt.len() - 1) == Some('<'.to_int()))
  assert_true(pt.code_unit_at(pt.len()) is None)
  assert_true(pt.code_unit_at(-1) is None)
}

///|
test "piece table boundary: empty doc, clamping, full delete" {
  let pt = @infra_text.PieceTable::from_string("")
  assert_eq(pt.len(), 0)
  pt.insert(99, "abc") // 夹取到 0
  assert_eq(pt.to_string(), "abc")
  pt.insert(-5, "x") // 夹取到 0
  assert_eq(pt.to_string(), "xabc")
  pt.delete(1, 100) // 夹取到文档尾
  assert_eq(pt.to_string(), "x")
  pt.delete(0, 1)
  assert_eq(pt.len(), 0)
  assert_eq(pt.to_string(), "")
  pt.insert(0, "") // 空插入无操作
  assert_eq(pt.len(), 0)
}

///|
test "piece table differential PBT vs naive string (250 iterations)" {
  let rng = @infra_pbt.rng_new(0xE6_9ECEUL)
  for _iter in 0..<250 {
    let pt = @infra_text.PieceTable::from_string("init-text ")
    let mut naive = "init-text "
    for _step in 0..<(10 + rng.next_below(40)) {
      if naive.length() == 0 || rng.next_below(3) != 0 {
        let off = rng.next_below(naive.length() + 1)
        let sb = StringBuilder::new()
        for _ in 0..<(1 + rng.next_below(8)) {
          sb.write_char((97 + rng.next_below(26)).unsafe_to_char())
        }
        let ins = sb.to_string()
        pt.insert(off, ins)
        naive = naive[0:off].to_owned() + ins + naive[off:].to_owned()
      } else {
        let off = rng.next_below(naive.length())
        let cnt = 1 + rng.next_below(naive.length() - off)
        pt.delete(off, cnt)
        naive = naive[0:off].to_owned() + naive[off + cnt:].to_owned()
      }
      assert_eq(pt.len(), naive.length())
    }
    assert_eq(pt.to_string(), naive)
    // 随机点查交叉验证。
    for _ in 0..<10 {
      if naive.length() > 0 {
        let off = rng.next_below(naive.length())
        assert_true(pt.code_unit_at(off) == Some(naive.at(off).to_int()))
      }
    }
  }
}

///|
test "piece table vs rope cross-differential (100 iterations)" {
  let rng = @infra_pbt.rng_new(0xE6_C205_5UL)
  for _iter in 0..<100 {
    let pt = @infra_text.PieceTable::from_string("seed")
    let r = @infra_text.Rope::from_string("seed")
    for _step in 0..<30 {
      if r.len() == 0 || rng.next_below(3) != 0 {
        let off = rng.next_below(r.len() + 1)
        let sb = StringBuilder::new()
        for _ in 0..<(1 + rng.next_below(6)) {
          sb.write_char((65 + rng.next_below(26)).unsafe_to_char())
        }
        let ins = sb.to_string()
        pt.insert(off, ins)
        r.insert(off, ins)
      } else {
        let off = rng.next_below(r.len())
        let cnt = 1 + rng.next_below(r.len() - off)
        pt.delete(off, cnt)
        r.delete(off, off + cnt)
      }
    }
    assert_eq(pt.len(), r.len())
    assert_eq(pt.to_string(), r.to_string())
  }
}
