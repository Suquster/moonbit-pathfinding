// evidence_test.mbt —— 证据索引引擎黑盒测试（H-4 + G-C2）。
//
// 覆盖：解析与断链诊断（字段数/空声明/无锚点/坏 commit）、
// SHA-256 摘要防篡改（增删改重排均改变摘要）、markdown 渲染、
// PBT（合法条目全量入索引且摘要确定性）。

///|
fn good_lines() -> Array[String] {
  [
    "zstd 帧 RFC 8878 往返|src/infra_compress::zstd roundtrip|8082826", "有界回溯与 Pike VM 差分一致|src/regex_engine::bounded vs pike|29234d2",
    "", "工作区增量重建最小性|src/build_tool::rebuild plan|2383342",
  ]
}

///|
test "parse_evidence：合法索引与摘要稳定性" {
  let idx = @evidence_index.parse_evidence(good_lines())
  assert_true(idx.is_sound())
  assert_eq(idx.entries.length(), 3)
  assert_eq(idx.entries[0].claim, "zstd 帧 RFC 8878 往返")
  // 摘要确定性：同输入两次解析摘要一致。
  let idx2 = @evidence_index.parse_evidence(good_lines())
  assert_eq(idx.digest(), idx2.digest())
  assert_eq(idx.digest().length(), 64)
}

///|
test "parse_evidence：断链诊断逐类命中" {
  let idx = @evidence_index.parse_evidence([
    "only-two-fields|x::y", "|src/a::t|8082826", "claim|no-anchor|8082826", "claim|src/a::t|ZZZ",
    "claim|src/a::t|abc",
  ])
  assert_eq(idx.entries.length(), 0)
  assert_eq(idx.diagnostics.length(), 5)
  assert_true(!idx.is_sound())
  assert_true(idx.diagnostics[0].contains("expected 3 fields"))
  assert_true(idx.diagnostics[1].contains("empty claim"))
  assert_true(idx.diagnostics[2].contains("missing `::` anchor"))
  assert_true(idx.diagnostics[3].contains("bad commit hash"))
  assert_true(idx.diagnostics[4].contains("bad commit hash"))
}

///|
test "digest：增删改重排均改变摘要" {
  let base = @evidence_index.parse_evidence(good_lines())
  // 删除一条。
  let removed = @evidence_index.parse_evidence([
    "zstd 帧 RFC 8878 往返|src/infra_compress::zstd roundtrip|8082826", "有界回溯与 Pike VM 差分一致|src/regex_engine::bounded vs pike|29234d2",
  ])
  assert_true(base.digest() != removed.digest())
  // 修改一个 commit。
  let mutated = @evidence_index.parse_evidence([
    "zstd 帧 RFC 8878 往返|src/infra_compress::zstd roundtrip|8082827", "有界回溯与 Pike VM 差分一致|src/regex_engine::bounded vs pike|29234d2",
    "工作区增量重建最小性|src/build_tool::rebuild plan|2383342",
  ])
  assert_true(base.digest() != mutated.digest())
  // 重排两条。
  let reordered = @evidence_index.parse_evidence([
    "有界回溯与 Pike VM 差分一致|src/regex_engine::bounded vs pike|29234d2",
    "zstd 帧 RFC 8878 往返|src/infra_compress::zstd roundtrip|8082826", "工作区增量重建最小性|src/build_tool::rebuild plan|2383342",
  ])
  assert_true(base.digest() != reordered.digest())
}

///|
test "render_markdown：证据表与防篡改摘要尾注" {
  let idx = @evidence_index.parse_evidence(good_lines())
  let md = idx.render_markdown()
  assert_true(
    md.contains(
      "| zstd 帧 RFC 8878 往返 | `src/infra_compress::zstd roundtrip` | 8082826 |",
    ),
  )
  assert_true(md.contains("条目 3 项"))
  assert_true(md.contains("sha256:" + idx.digest()))
}

///|
test "PBT：随机合法条目全量入索引且摘要确定（100 迭代）" {
  let gen : @infra_pbt.Gen[Array[String]] = @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_below(20)
    let lines : Array[String] = []
    for i in 0..<n {
      lines.push(
        "claim-" +
        i.to_string() +
        "|src/pkg" +
        rng.next_below(9).to_string() +
        "::test " +
        rng.next_below(100).to_string() +
        "|abc1234",
      )
    }
    lines
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(lines) {
    let idx = @evidence_index.parse_evidence(lines)
    idx.is_sound() &&
    idx.entries.length() == lines.length() &&
    idx.digest() == @evidence_index.parse_evidence(lines).digest()
  })
  assert_true(ok)
}
