// examples/text_editor_core — runnable demonstration of the
// `src/infra_text` + `src/infra_ds` directions as an editor-backend
// workflow: edit a buffer through a rope with line/column mapping, apply
// the same edits through a piece table, segment graphemes and compute
// terminal display width, produce a Myers character diff, and back the
// editor with LRU / bloom / roaring-bitmap indexes.
//
// Run with:
//   moon run examples/text_editor_core

///|
fn main {
  println("=== 1. rope editing with line/column mapping ===")
  let rope = @text.Rope::from_string("fn main {\n  todo\n}\n")
  rope.delete(12, 16) // half-open range [12, 16) removes "todo"
  rope.insert(12, "println(\"hi\")")
  println("buffer after edit:\n\{rope.to_string()}")
  println(
    "len \{rope.len()}, lines \{rope.line_count()}, depth \{rope.depth()}",
  )
  let (line, col) = rope.line_col_at(14)
  println("offset 14 -> line \{line}, col \{col}")
  println("line 1 starts at offset \{rope.offset_of_line(1)}")
  println("")
  println("=== 2. piece table applies the same edit ===")
  let pt = @text.PieceTable::from_string("fn main {\n  todo\n}\n")
  pt.delete(12, 4)
  pt.insert(12, "println(\"hi\")")
  println("piece table == rope: \{pt.to_string() == rope.to_string()}")
  println("pieces: \{pt.piece_count()}, len: \{pt.len()}")
  println("")
  println("=== 3. graphemes + display width ===")
  let s = "héllo 世界"
  println("string       : \{s}")
  println("graphemes    : \{@text.grapheme_count(s)}")
  println("display width: \{@text.display_width(s)} (CJK counts as 2 cells)")
  println("case-fold eq : \{@text.eq_fold("HÉLLO 世界", s)}")
  println("")
  println("=== 4. Myers character diff ===")
  let before = "let x = compute(a, b)"
  let after = "let x = compute(a, b, c)"
  let ops = @text.myers_diff(before, after)
  println("edit cost: \{@text.diff_edit_cost(ops)}")
  println("apply(diff) == after : \{@text.diff_apply(ops) == after}")
  println("source(diff) == before: \{@text.diff_source(ops) == before}")
  println("")
  println("=== 5. LRU cache for rendered lines ===")
  let cache : @ds.LruCache[Int, String] = @ds.LruCache::create(2)
  cache.put(1, "render:line-1")
  cache.put(2, "render:line-2")
  let _ = cache.get(1) // touch 1 so 2 becomes LRU
  cache.put(3, "render:line-3") // evicts 2
  let hit1 = match cache.get(1) {
    Some(_) => "hit"
    None => "miss"
  }
  let hit2 = match cache.get(2) {
    Some(_) => "hit"
    None => "miss (evicted)"
  }
  println(
    "line 1: \{hit1}, line 2: \{hit2}, size \{cache.size()}/\{cache.cap()}",
  )
  println("")
  println("=== 6. bloom filter + roaring bitmap indexes ===")
  let bloom = @ds.BloomFilter::create(1024, 3)
  bloom.insert("symbol:main")
  bloom.insert("symbol:rope")
  println("bloom has 'symbol:main' : \{bloom.contains("symbol:main")}")
  println("bloom has 'symbol:nope' : \{bloom.contains("symbol:nope")}")
  let dirty_lines = @ds.RoaringBitmap::new()
  let _ = dirty_lines.add(1)
  let _ = dirty_lines.add(2)
  let _ = dirty_lines.add(100000)
  let visible = @ds.RoaringBitmap::new()
  let _ = visible.add(2)
  let _ = visible.add(3)
  let redraw = dirty_lines.intersect_with(visible)
  println(
    "dirty ∩ visible lines: \{redraw.to_array().map(fn(v) { v.to_string() }).join(", ")} (cardinality \{redraw.cardinality()})",
  )
}
