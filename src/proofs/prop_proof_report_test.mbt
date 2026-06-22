// Feature: championship-v1-upgrade, Property 16: 证明报告往返一致与失败聚合
//
// prop_proof_report_test.mbt —— 证明报告往返 / 聚合属性测试（任务 13.2）。
//
//   Property 16: 证明报告往返一致与失败聚合
//   ------------------------------------------------------------------
//   *对任意* `ProofReport`：
//     (1) 往返一致：`from_json(to_json(report))` 成功，且还原结果与原报告
//         逐字段相等（`backends` / `moon_version` / `generated_at` / `entries`
//         全部一一对应，含 `generated_at` 字段）；
//     (2) 条目数对齐：`to_markdown` 产出的表格数据行数 == JSON 条目数
//         （二者均等于 `report.entries` 的长度，体现「逐项语义一致」R11.1）；
//     (3) 失败聚合：`any_failed` 当且仅当存在 `passed == false` 的条目时为真
//         （空报告视为未失败 · R11.4）。
//
//   对应 Requirement 11.1「生成 Markdown 与 JSON 两种逐项语义一致的报告」与
//   Requirement 11.4「失败聚合（存在失败条目即判真）」。
//
// 生成器说明：
//   * 以 `@infra_pbt.Gen` + 确定性 `Rng` 随机构造 `ProofReport`，含随机条数
//     `entries`、随机后端列表、随机版本 / 时间戳字符串。
//   * 字段字符串取自一个**刻意包含 JSON 转义触发字符**的字母表（`"` / `\` /
//     `\t` / 控制字符 / 非 ASCII），以充分驱动 `to_json` 的转义与 `from_json`
//     的反转义路径；但**排除换行符 `\n`**，从而使 Markdown「表格数据行计数」
//     （按行首 `|` 计数再扣除表头 + 分隔两行）保持鲁棒、与条目数严格对齐。
//   * `passed` 由 `next_bool` 随机取值，使 `any_failed` 的真 / 假两支均被覆盖。
//
// **Validates: Requirements 11.1, 11.4**

///|
/// 单元字符字母表：覆盖普通字符 + JSON 转义触发字符（引号 / 反斜杠 / 制表符 /
/// 控制字符 / 非 ASCII BMP 字符），**不含换行符**以保证 Markdown 行计数鲁棒。
fn pr16_alphabet() -> Array[Char] {
  [
    'a',
    'b',
    'c',
    '1',
    ' ',
    '|',
    '"',
    '\\',
    '\t',
    '/',
    (0x01).unsafe_to_char(),
    (0x08).unsafe_to_char(),
    (0x0C).unsafe_to_char(),
    (0x1F).unsafe_to_char(),
    '中',
    'é',
  ]
}

///|
/// 由随机源生成长度 `[0, max_len]` 的随机字符串，字符取自 `pr16_alphabet`。
/// 长度可为 0（覆盖空字符串边界），全程以 `@infra_text.TextBuilder` 追加构建，
/// 循环体内仅 `push_char`，无字符串 `+` 累加（Requirement 22.4）。
fn pr16_gen_string(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let alpha = pr16_alphabet()
  let n = rng.next_range(0, max_len)
  let tb = @infra_text.TextBuilder::new()
  for _i in 0..<n {
    tb.push_char(alpha[rng.next_below(alpha.length())])
  }
  tb.build()
}

///|
/// 随机生成后端列表：长度 `[0, 4]`，元素取自 `wasm-gc` / `js` / `native`
/// 子集（R11.3），允许重复（往返按顺序逐一保留，等价性不受影响）。
fn pr16_gen_backends(rng : @infra_pbt.Rng) -> Array[String] {
  let pool = ["wasm-gc", "js", "native"]
  let n = rng.next_range(0, 4)
  let out : Array[String] = []
  for _i in 0..<n {
    out.push(pool[rng.next_below(pool.length())])
  }
  out
}

///|
/// 随机生成一条 `ProofEntry`：四个字符串字段随机，`passed` 随机布尔。
fn pr16_gen_entry(rng : @infra_pbt.Rng) -> ProofEntry {
  {
    algorithm: pr16_gen_string(rng, 6),
    property: pr16_gen_string(rng, 8),
    passed: rng.next_bool(),
    evidence: pr16_gen_string(rng, 6),
  }
}

///|
/// 随机生成一个 `ProofReport`：条目数 `[0, 6]`，覆盖空报告到多条目报告。
fn pr16_gen_report(rng : @infra_pbt.Rng) -> ProofReport {
  let count = rng.next_range(0, 6)
  let entries : Array[ProofEntry] = []
  for _i in 0..<count {
    entries.push(pr16_gen_entry(rng))
  }
  {
    backends: pr16_gen_backends(rng),
    moon_version: pr16_gen_string(rng, 6),
    generated_at: pr16_gen_string(rng, 10),
    entries,
  }
}

///|
/// 统计 Markdown 文本中「以 `|` 开头的行」数。`to_markdown` 的表格部分恰由
/// 表头行、分隔行以及每条目一行构成，且这些行均以 `|` 起始；其余行（标题 /
/// 元信息 / 汇总）均以 `#` 或 `-` 起始。由于单元内容不含换行符，故表格数据
/// 行数 == 本计数 - 2（扣除表头与分隔行）。
fn pr16_count_pipe_lines(md : String) -> Int {
  let mut count = 0
  let mut at_line_start = true
  for c in md {
    if at_line_start && c == '|' {
      count = count + 1
    }
    at_line_start = c == '\n'
  }
  count
}

///|
/// `any_failed` 的**独立参照实现**：直接扫描是否存在 `passed == false` 的条目，
/// 用于与被测 `ProofReport::any_failed` 做「当且仅当」等价性交叉验证。
fn pr16_any_failed_ref(report : ProofReport) -> Bool {
  let mut found = false
  for e in report.entries {
    if !e.passed {
      found = true
    }
  }
  found
}

///|
/// 单次场景：随机构造报告并校验 Property 16 的三个分量。返回 `true` 表示本次
/// 随机实例下往返一致、条目数对齐、失败聚合全部成立。
fn pr16_scenario(rng : @infra_pbt.Rng) -> Bool {
  let report = pr16_gen_report(rng)

  // —— 分量 (1)：JSON 往返逐字段相等 ——
  let json = report.to_json()
  let restored = match ProofReport::from_json(json) {
    Ok(r) => r
    Err(_) => return false // to_json 的产物必可被 from_json 还原。
  }
  if restored != report {
    return false
  }

  // —— 分量 (2)：Markdown 表格数据行数 == JSON 条目数（== entries 长度）——
  let json_count = restored.entries.length()
  let md = report.to_markdown()
  let md_rows = pr16_count_pipe_lines(md) - 2 // 扣除表头行与分隔行
  if md_rows != json_count {
    return false
  }
  if md_rows != report.entries.length() {
    return false
  }

  // —— 分量 (3)：any_failed 当且仅当存在 passed == false 的条目 ——
  if report.any_failed() != pr16_any_failed_ref(report) {
    return false
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 16: 证明报告往返一致与失败聚合
/// （holds_for_all 模板，iters ≥ 100）
///
/// **Validates: Requirements 11.1, 11.4**
test "Feature: championship-v1-upgrade, Property 16: proof report round-trips field-equal, markdown rows equal JSON entries, and any_failed is true iff a failing entry exists" {
  let gen = @infra_pbt.Gen::new(fn(rng) { pr16_scenario(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }, iters=100))
}
