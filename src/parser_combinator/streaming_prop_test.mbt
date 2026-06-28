// streaming_prop_test.mbt —— L1 流式 / 增量输入属性测试与 EOF 边界单元测试
// （tasks 10.2, 10.3, 10.4）。
//
// 实现 Property 26（流式分段无关性）、Property 27（需要更多输入而非误报失败），
// 并补充流式 EOF 失败边界单元测试（R10.4）。见证文法：`'<' digits '>'`
// （严格序列，使任一真前缀在数据边界失败 → 触发 NeedMore）。

///|
/// 流式见证文法：`'<' digits '>'` → 产出该数字（借 L0 between + dp_number）。
fn stream_num_grammar() -> Grammar[Int] {
  lift(between(pchar('<'), dp_number(), pchar('>')))
}

///|
/// 把字符串随机切分为非空分段（concat 后等于原串）；避免空段（空段在本实现
/// 中约定为「结束信号」）。
fn split_nonempty(rng : @infra_pbt.Rng, s : String) -> Array[String] {
  let chunks : Array[String] = []
  let mut cur = ""
  for c in s {
    cur = cur + "\{c}"
    if rng.next_bool() && cur != "" {
      chunks.push(cur)
      cur = ""
    }
  }
  if cur != "" {
    chunks.push(cur)
  }
  if chunks.length() == 0 {
    chunks.push(s)
  }
  chunks
}

///|
/// 流式结果与一次性结果的逐字段比较（成功比值与剩余偏移、失败比位置与期望）。
fn stream_result_eq(a : ParseResult[Int], b : ParseResult[Int]) -> Bool {
  presult_eq(a, b)
}

///|
/// Feature: parser-combinator, Property 26: 流式分段无关性
///
/// 对任意完整输入及其任意分段方式，增量喂入（`run_incremental` + 逐段 `drive`，
/// 结束时 closed）所得的最终解析结果与一次性喂入完整输入的结果逐字段一致。
///
/// **Validates: Requirements 10.1, 10.3, 10.5**
test "Feature: parser-combinator, Property 26: streaming segmentation independence" {
  let g = stream_num_grammar()
  let gen = @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(0, 9999)
    let full = "<" + "\{n}" + ">"
    (full, split_nonempty(rng, full))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(pair) {
    let (full, chunks) = pair
    let rest : Array[String] = []
    let mut i = 1
    while i < chunks.length() {
      rest.push(chunks[i])
      i = i + 1
    }
    let incremental = drive(g.run_incremental(chunks[0]), rest, closed=true)
    let oneshot = g.run_naive_string(full)
    stream_result_eq(incremental, oneshot)
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 27: 需要更多输入而非误报失败
///
/// 对任意「某合法完整输入的真前缀且尚未标记结束」的分段，`run_incremental`
/// 返回 `NeedMore` 续延，而非报告语法失败。
///
/// **Validates: Requirements 10.2**
test "Feature: parser-combinator, Property 27: needs-more-input rather than false failure" {
  let g = stream_num_grammar()
  let gen = @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(0, 9999)
    let full = "<" + "\{n}" + ">"
    let chars = full.iter().to_array()
    let k = rng.next_range(0, chars.length() - 1) // 真前缀长度 [0, len-1]
    let mut prefix = ""
    let mut i = 0
    while i < k {
      prefix = prefix + "\{chars[i]}"
      i = i + 1
    }
    prefix
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(prefix) {
    match g.run_incremental(prefix) {
      NeedMore(_) => true
      Done(_) => false
    }
  })
  assert_true(ok)
}

///|
/// 流式 EOF 失败边界：标记结束（closed）且仍不满足解析器 → `Done(Fail)`，
/// 不误报 NeedMore（R10.4）；补足缺失数据后再结束 → 成功。
test "streaming reports failure at EOF when unsatisfied" {
  let g = stream_num_grammar()
  // "<12" 缺失 '>'：分段耗尽并 close → 失败。
  match drive(g.run_incremental("<12"), [], closed=true) {
    Fail(pos, ..) => @test.assert_eq(pos.offset, 3)
    Ok(_, _) => fail("expected failure at EOF for incomplete input")
  }
  // 补足 ">" 后结束 → 成功产出 12。
  match drive(g.run_incremental("<12"), [">"], closed=true) {
    Ok(v, _) => @test.assert_eq(v, 12)
    Fail(_, ..) => fail("expected success once '>' arrives")
  }
}
