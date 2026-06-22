// Feature: championship-v1-upgrade, Property 6: 基准报告 JSON 序列化往返一致
//
// prop_report_roundtrip_test.mbt —— 任务 6.4：基准报告往返属性测试。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 6「基准报告 JSON 序列化往返一致」（Validates: Requirements 5.1）：
//
//   *对任意* `BenchReport`，`to_json` 产出的文本可被 `from_json` / `parse_report`
//   解析回结构，且与原报告 **逐字段相等**（依赖 derive Eq）；同时 `to_markdown`
//   产出 **非空** 文本，并 **为每个用例产出恰好一行** 数据行。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板。每条属性
// 显式以 `iters=100` 驱动（满足「每条属性 ≥100 次迭代」基线）。
//
// 生成器约定：
//   * 元信息字符串字段（moon_version / backend / os / cpu / generator）刻意混入
//     会触发 JSON 转义的字符（引号 `"`、反斜杠 `\`、换行、制表、回车），以充分
//     覆盖序列化转义与反序列化反转义的往返路径；字符集不含竖线 `|`，避免污染
//     Markdown 表格的「数据行」统计。
//   * `algorithm` 出现在 Markdown 表格行内，故仅取字母 / 数字安全字符（不含竖线、
//     不含换行），保证「数据行数 = 用例数」可被逐行精确统计。
//   * 每个用例的 `raw_ns` 为 **非空** 有限浮点数组；`stats` 由
//     `compute_stats(raw_ns)` 纯计算得出（输入非空，必为 `Ok`）。
//   * 浮点的「序列化再解析」往返由实现保证（`Double::to_string` 与
//     `@strconv.parse_double` 互逆），生成时直接采用 rng 产生的有限值。

// ---------------------------------------------------------------------------
// 随机生成器（generator）—— 复用 @infra_pbt 种子驱动随机源 Rng
// ---------------------------------------------------------------------------

///|
/// 生成一个「含转义场景」的随机字符串（长度落在 `[0, max_len]`）。
///
/// 字符集刻意混入 `"` / `\` / 换行 / 制表 / 回车，以覆盖 JSON 转义往返；
/// 不含竖线 `|`，避免干扰 Markdown 表格数据行统计。
fn rr_gen_escapable_string(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let charset = [
    'a', 'b', 'c', 'Z', 'Q', '0', '1', '2', ' ', '_', '/', '"', '\\', '\n', '\t',
    '\r',
  ]
  let len = rng.next_below(max_len + 1)
  let buf : Array[Char] = []
  let mut i = 0
  while i < len {
    buf.push(charset[rng.next_below(charset.length())])
    i = i + 1
  }
  String::from_array(buf)
}

///|
/// 生成一个出现在 Markdown 表格行内的安全算法名（长度 `[1, max_len]`）。
///
/// 仅取字母 / 数字，绝不含竖线或换行，保证表格「数据行数 = 用例数」可精确统计。
fn rr_gen_algorithm(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let charset = [
    'D', 'i', 'j', 'k', 's', 't', 'r', 'a', 'A', 'S', 'B', 'F', '0', '9',
  ]
  let len = rng.next_range(1, max_len)
  let buf : Array[Char] = []
  let mut i = 0
  while i < len {
    buf.push(charset[rng.next_below(charset.length())])
    i = i + 1
  }
  String::from_array(buf)
}

///|
/// 生成一个有限的非负浮点计时样本（含小数部分），保证 `to_string`/`parse_double`
/// 往返无损，且不会溢出为非有限值。
fn rr_gen_double(rng : @infra_pbt.Rng) -> Double {
  let whole = rng.next_range(0, 1_000_000).to_double()
  let frac = rng.next_below(1000).to_double() / 1000.0
  whole + frac
}

///|
/// 生成一个非空的随机浮点数组（长度落在 `[1, max_len]`）。
fn rr_gen_raw_ns(rng : @infra_pbt.Rng, max_len : Int) -> Array[Double] {
  let len = rng.next_range(1, max_len)
  let arr : Array[Double] = []
  let mut i = 0
  while i < len {
    arr.push(rr_gen_double(rng))
    i = i + 1
  }
  arr
}

///|
/// 生成单个随机 `BenchCase`：随机算法名 / 规模 / 边数 / 查询数 / 种子 /
/// 非空原始计时数组 / 由 `compute_stats` 计算的统计量。
fn rr_gen_case(rng : @infra_pbt.Rng) -> BenchCase {
  let algorithm = rr_gen_algorithm(rng, 8)
  let graph_size = rng.next_range(0, 100_000)
  let edge_count = rng.next_range(0, 100_000)
  let query_count = rng.next_range(0, 100_000)
  let seed = rng.next()
  let raw_ns = rr_gen_raw_ns(rng, 12)
  // raw_ns 非空，compute_stats 必为 Ok（空样本才会 Err）。
  guard compute_stats(raw_ns) is Ok(stats)
  { algorithm, graph_size, edge_count, query_count, seed, raw_ns, stats }
}

///|
/// 生成一个随机 `BenchReport`：元信息字符串（含转义场景）+ 随机预热次数 +
/// `1..N` 个随机用例。
fn rr_gen_report(rng : @infra_pbt.Rng) -> BenchReport {
  let moon_version = rr_gen_escapable_string(rng, 10)
  let backend = rr_gen_escapable_string(rng, 10)
  let os = rr_gen_escapable_string(rng, 10)
  let cpu = rr_gen_escapable_string(rng, 10)
  let generator = rr_gen_escapable_string(rng, 12)
  let warmup_count = rng.next_range(0, 20)
  let case_count = rng.next_range(1, 5)
  let cases : Array[BenchCase] = []
  let mut i = 0
  while i < case_count {
    cases.push(rr_gen_case(rng))
    i = i + 1
  }
  { moon_version, backend, os, cpu, generator, warmup_count, cases }
}

///|
/// 随机 `BenchReport` 生成器（封装为 @infra_pbt.Gen，供断言模板驱动）。
fn rr_report_gen() -> @infra_pbt.Gen[BenchReport] {
  @infra_pbt.Gen::new(fn(rng) { rr_gen_report(rng) })
}

// ---------------------------------------------------------------------------
// 辅助：统计 Markdown 表格「数据行」数量
// ---------------------------------------------------------------------------

///|
/// 统计以 "| " 开头的物理行数（含表头行与分隔行）。
///
/// `to_markdown` 的表格由 1 个表头行 + 1 个分隔行 + 每用例 1 行数据行构成，
/// 故「数据行数 = 以 "| " 开头的行数 - 2」。算法名不含竖线 / 换行、元信息字符
/// 集不含竖线，保证统计精确。
fn rr_count_pipe_lines(md : String) -> Int {
  let chars : Array[Char] = []
  for c in md {
    chars.push(c)
  }
  let n = chars.length()
  let mut count = 0
  let mut at_line_start = true
  let mut i = 0
  while i < n {
    if at_line_start && chars[i] == '|' && i + 1 < n && chars[i + 1] == ' ' {
      count = count + 1
    }
    at_line_start = chars[i] == '\n'
    i = i + 1
  }
  count
}

// ---------------------------------------------------------------------------
// 属性断言（每条 ≥100 次迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: championship-v1-upgrade, Property 6: 基准报告 JSON 序列化往返一致
///
/// 对任意 `BenchReport`，`from_json(to_json(report))` 应恰好为 `Ok(report)`
/// （逐字段相等，依赖 derive Eq；`generated_at` 时间戳不参与结构等值）。
///
/// **Validates: Requirements 5.1**
test "Feature: championship-v1-upgrade, Property 6: from_json(to_json(report)) equals Ok(report)" {
  let ok = @infra_pbt.holds_for_all(
    rr_report_gen(),
    fn(report) {
      let json = report.to_json()
      BenchReport::from_json(json) == Ok(report)
    },
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 6: 基准报告 JSON 序列化往返一致
///
/// 经别名入口 `parse_report` 同样满足往返：对任意 `BenchReport`，
/// `parse_report(to_json(report))` 应恰好为 `Ok(report)`。
///
/// **Validates: Requirements 5.1**
test "Feature: championship-v1-upgrade, Property 6: parse_report(to_json(report)) equals Ok(report)" {
  let ok = @infra_pbt.holds_for_all(
    rr_report_gen(),
    fn(report) { parse_report(report.to_json()) == Ok(report) },
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 6: 基准报告 JSON 序列化往返一致
///
/// 对任意 `BenchReport`，`to_markdown(report)` 应为 **非空** 文本，且其表格
/// **数据行数恰等于用例数量**（以 "| " 开头的物理行数减去表头行与分隔行）。
///
/// **Validates: Requirements 5.1**
test "Feature: championship-v1-upgrade, Property 6: to_markdown is non-empty with one data row per case" {
  let ok = @infra_pbt.holds_for_all(
    rr_report_gen(),
    fn(report) {
      let md = report.to_markdown()
      let data_rows = rr_count_pipe_lines(md) - 2
      md.length() > 0 && data_rows == report.cases.length()
    },
    iters=100,
  )
  assert_true(ok)
}
