// rope_sync_test.mbt —— T5.1 rope 化增量同步的等价性与边界锁定。
//
// 核心保证：对任意 `(doc, changes, enc)`，`RopeDocument::apply_changes` 与
// 既有 `apply_changes`（sync.mbt，O(N) 参照实现）结果逐字符一致——成功时
// 文本相等，失败时同样返回 `Err`（不产生部分应用）。

///|
/// 内部辅助：并跑 rope 与参照实现，断言结果一致；返回是否一致。
fn rope_matches_reference(
  doc : String,
  changes : Array[ContentChange],
  enc : PositionEncoding,
) -> Bool {
  let ref_result = apply_changes(doc, changes, enc)
  let rope_result = RopeDocument::from_string(doc).apply_changes(changes, enc)
  match (ref_result, rope_result) {
    (Ok(a), Ok(b)) => a == b.to_string()
    (Err(_), Err(_)) => true
    _ => false
  }
}

///|
test "T5.1: rope 单条区间替换与参照实现一致（含换行跨行）" {
  let doc = "hello\nworld\nfoo"
  let change : ContentChange = {
    range: Some({
      start: { line: 0, character: 2 },
      end: { line: 1, character: 3 },
    }),
    text: "XY\nZ",
  }
  assert_true(rope_matches_reference(doc, [change], Utf16))
  // 具体值锁定。
  match RopeDocument::from_string(doc).apply_change(change, Utf16) {
    Ok(d) => assert_eq(d.to_string(), "heXY\nZld\nfoo")
    Err(_) => fail("不应失败")
  }
}

///|
test "T5.1: rope Full 替换、行尾/文末边界、空文本删除" {
  // Full 替换。
  let full : ContentChange = { range: None, text: "all new" }
  assert_true(rope_matches_reference("old\ntext", [full], Utf16))
  // 行尾插入（列号 == 行长）。
  let eol : ContentChange = {
    range: Some({
      start: { line: 0, character: 5 },
      end: { line: 0, character: 5 },
    }),
    text: "!",
  }
  assert_true(rope_matches_reference("hello\nworld", [eol], Utf16))
  // 文末追加。
  let eof : ContentChange = {
    range: Some({
      start: { line: 1, character: 5 },
      end: { line: 1, character: 5 },
    }),
    text: "?",
  }
  assert_true(rope_matches_reference("hello\nworld", [eof], Utf16))
  // 区间删除（text 为空）。
  let del : ContentChange = {
    range: Some({
      start: { line: 0, character: 1 },
      end: { line: 0, character: 4 },
    }),
    text: "",
  }
  assert_true(rope_matches_reference("hello", [del], Utf16))
}

///|
test "T5.1: rope 多码元字符——emoji 列号在 UTF-8/16/32 下均与参照一致" {
  // U+1F600 在 UTF-16 占 2 码元、UTF-8 占 4、UTF-32 占 1。
  let doc = "a😀b\ncd"
  for enc in ([Utf8, Utf16, Utf32] : Array[PositionEncoding]) {
    // 合法：紧跟 emoji 之后（各编码列号不同）。
    let col = match enc {
      Utf8 => 5
      Utf16 => 3
      Utf32 => 2
    }
    let ins : ContentChange = {
      range: Some({
        start: { line: 0, character: col },
        end: { line: 0, character: col },
      }),
      text: "X",
    }
    assert_true(rope_matches_reference(doc, [ins], enc))
  }
  // 非法：UTF-16 下列号 2 落在 emoji 的两个码元中间 → 双方一致返回 Err。
  let bad : ContentChange = {
    range: Some({
      start: { line: 0, character: 2 },
      end: { line: 0, character: 2 },
    }),
    text: "X",
  }
  assert_true(rope_matches_reference(doc, [bad], Utf16))
}

///|
test "T5.1: rope 错误语义——越界 / start>end 与参照一致返回 Err" {
  let doc = "ab\ncd"
  let oob_line : ContentChange = {
    range: Some({
      start: { line: 9, character: 0 },
      end: { line: 9, character: 0 },
    }),
    text: "X",
  }
  let oob_col : ContentChange = {
    range: Some({
      start: { line: 0, character: 99 },
      end: { line: 0, character: 99 },
    }),
    text: "X",
  }
  let inverted : ContentChange = {
    range: Some({
      start: { line: 1, character: 1 },
      end: { line: 0, character: 0 },
    }),
    text: "X",
  }
  assert_true(rope_matches_reference(doc, [oob_line], Utf16))
  assert_true(rope_matches_reference(doc, [oob_col], Utf16))
  assert_true(rope_matches_reference(doc, [inverted], Utf16))
  // 多条变更中途失败 → 双方一致不产生部分应用。
  let good : ContentChange = {
    range: Some({
      start: { line: 0, character: 0 },
      end: { line: 0, character: 1 },
    }),
    text: "Z",
  }
  assert_true(rope_matches_reference(doc, [good, oob_line], Utf16))
}

///|
/// 随机文档生成器：含换行与 emoji 的短文本。
fn gen_rope_doc() -> @infra_pbt.Gen[String] {
  let alphabet = ['a', 'b', 'c', '\n', 'x', '😀', 'y', '\n', '0', '中']
  @infra_pbt.Gen::new(fn(rng) {
    let len = rng.next_range(0, 40)
    let sb = StringBuilder::new()
    let mut i = 0
    while i < len {
      sb.write_char(alphabet[rng.next_below(alphabet.length())])
      i = i + 1
    }
    sb.to_string()
  })
}

///|
/// Feature: moonbit-infra-suite, T5.1: rope 与 O(N) 参照实现的全等价属性
///
/// 对任意随机文档与随机（可能非法的）变更序列，rope 实现与参照实现在三种
/// 位置编码下结果逐字符一致（成功同文本 / 失败同 Err）。
///
/// **Validates: Requirements 10.4, 10.5（T5.1）**
test "T5.1 property: rope apply_changes ≡ reference apply_changes (100 iters)" {
  let ok = @infra_pbt.holds_for_all(gen_rope_doc(), fn(doc) {
    let rng = @infra_pbt.rng_new((doc.length() * 7919 + 17).to_uint64())
    let mut all_ok = true
    for enc in ([Utf8, Utf16, Utf32] : Array[PositionEncoding]) {
      // 每份文档派生 3 条随机变更（位置可能越界，覆盖错误路径）。
      let changes : Array[ContentChange] = []
      let mut k = 0
      while k < 3 {
        let sl = rng.next_range(0, 5)
        let sc = rng.next_range(0, 8)
        let el = rng.next_range(0, 5)
        let ec = rng.next_range(0, 8)
        let txt = if rng.next_below(3) == 0 { "" } else { "n\nw" }
        changes.push({
          range: Some({
            start: { line: sl, character: sc },
            end: { line: el, character: ec },
          }),
          text: txt,
        })
        k = k + 1
      }
      // 整序列等价 + 单条等价都校验。
      if !rope_matches_reference(doc, changes, enc) {
        all_ok = false
      }
      for ch in changes {
        if !rope_matches_reference(doc, [ch], enc) {
          all_ok = false
        }
      }
    }
    // 往返：from_string/to_string 无损。
    all_ok && RopeDocument::from_string(doc).to_string() == doc
  })
  assert_true(ok)
}

///|
test "T5.1: rope 元数据——length/line_count 与文本一致" {
  let d = RopeDocument::from_string("ab\ncd\n")
  assert_eq(d.length(), 6)
  assert_eq(d.line_count(), 3) // "ab" / "cd" / ""（尾随换行后的空行）
  let e = RopeDocument::from_string("")
  assert_eq(e.length(), 0)
  assert_eq(e.line_count(), 1)
}
