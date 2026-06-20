// prop_sync_equiv_test.mbt —— 增量与全量等价属性测试（任务 7.3，Property 5）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 5「增量与全量等价」：
//
//   *对任意* 由生成器产出的（初始文本, 合法增量变更序列）对，
//     1. 依次应用增量变更所得文本 `inc = apply_changes(text0, changes, enc)`，
//        与**独立参照实现**逐字符算出的期望终文本 `expected` 相等
//        （体现真实的增量应用语义，使属性非平凡）；
//     2. 以变更后全文做一次全量替换所得文本
//        `full = apply_changes(text0, [{ range: None, text: inc }], enc)`
//        与增量结果 `inc` 逐字符相等（增量＝全量等价的核心断言）；
//     3. 该等价在诊断上的投影同样成立：增量结果文本的诊断序列与全量替换结果
//        文本的诊断序列逐条相等（`analyze(inc).diagnostics ==
//        analyze(full).diagnostics`，Requirement 9.3 的诊断投影）。
//
// **Validates: Requirements 3.2, 3.4, 3.6, 9.3**
//
// ── 「合法增量变更序列」生成策略（保证属性非平凡且可靠）──────────────────────
// 本文件为黑盒测试，仅依赖 sync.mbt / dsl.mbt 的公开 API（`apply_changes` /
// `ContentChange` / `analyze` / `TextDocument`）与 position_encoding.mbt 的
// `PositionEncoding`，不触碰任何私有内部工具。复用同包既有 PBT 辅助
// （`code_point_pool` / `gen_code_point` / `gen_lines` / `build_text` /
// `char_col` / `gen_encoding`，均来自 prop_position_offset_test.mbt，**不重定义**）。
//
// 为确保每条增量变更的 `range` 都**恰好落在码位边界上**（而非多码元字符中间，
// 否则 `apply_changes` 返回 `Err`、属性平凡失败），生成器**自行维护文本的码位
// 行结构**并据此构造变更：
//   1. 用 `gen_lines` 生成初始「行」结构 `lines : Array[Array[Int]]`（每行一段
//      不含 '\n' 的码位序列），用 `build_text` 拼出初始文本 `text0`；用
//      `gen_encoding` 取一个位置编码 `enc`。
//   2. 生成 1..3 条变更，**每条都作用于「上一条变更后」的行结构**（与
//      `apply_changes` 逐条作用语义一致）：随机选一行 `li` 与该行内两个**码位
//      边界索引** `ci_start <= ci_end`，用 `char_col` 在 `enc` 下把它们换算为
//      合法列号，构成单行 `range`（必为合法边界）；随机生成 0..3 个码位作为替换
//      文本 `repl`（取自 `code_point_pool`，不含 '\n'，保持行结构稳定）。
//   3. **独立参照**：在码位行结构上直接做切割
//      `new_line = line[0:ci_start] ++ repl ++ line[ci_end:]` 更新 `lines`；
//      全部变更应用完后由 `build_text(lines)` 得到期望终文本 `expected`。
//      该参照走「码位索引直接切割」路径，与 `apply_changes` 的「列号→码位索引→
//      切割」路径互相独立，故 `inc == expected` 是对增量应用语义的真实校验。
// 码位池（`code_point_pool`）刻意覆盖 ASCII、拉丁补充（é）、CJK（中/文）、emoji
// （😀/💩，UTF-16 代理对、UTF-8 四字节）、CJK 扩展 B（𠀀），故变更真正覆盖含
// 多字节 / 代理对 / 多行的有效区间，而非仅 ASCII 单行平凡样本。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `holds_for_all` 模板（默认 `iters=100`，
// 满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。

// ---------------------------------------------------------------------------
// 新增局部辅助（与既有 helper 不重名）
// ---------------------------------------------------------------------------

///|
/// 由一段码位序列重建文本（无换行）。复用 `build_text`：单行结构即纯码位串。
fn cps_line_to_text(cps : Array[Int]) -> String {
  build_text([cps])
}

///|
/// 在行结构 `lines` 上对第 `li` 行的码位区间 `[ci_start, ci_end)` 施加替换：
/// 以 `repl` 替换该区间，原地更新 `lines[li]`（独立于 `apply_changes` 的参照切割）。
fn splice_line(
  lines : Array[Array[Int]],
  li : Int,
  ci_start : Int,
  ci_end : Int,
  repl : Array[Int],
) -> Unit {
  let line = lines[li]
  let m = line.length()
  let new_line : Array[Int] = []
  for k in 0..<ci_start {
    new_line.push(line[k])
  }
  for x in repl {
    new_line.push(x)
  }
  for k in ci_end..<m {
    new_line.push(line[k])
  }
  lines[li] = new_line
}

// ---------------------------------------------------------------------------
// 随机生成器（初始文本 + 编码 + 合法增量变更序列 + 独立参照终文本）
// ---------------------------------------------------------------------------

///|
/// 生成一个样本：（初始文本 text0, 编码 enc, 增量变更序列 changes, 期望终文本 expected）。
///
/// changes 中每条变更的 `range` 均落在「上一条变更后」文本的合法码位边界上，
/// expected 由码位行结构独立切割算出（不依赖 `apply_changes`）。
fn gen_sync_sample(
  rng : @infra_pbt.Rng,
) -> (String, PositionEncoding, Array[ContentChange], String) {
  let lines = gen_lines(rng)
  let text0 = build_text(lines) // 在 lines 被后续变更改写前快照初始文本
  let enc = gen_encoding(rng)
  let n_changes = rng.next_range(1, 3) // 1..3 条变更
  let changes : Array[ContentChange] = []
  let mut c = 0
  while c < n_changes {
    let li = rng.next_below(lines.length())
    let line = lines[li]
    let m = line.length()
    // 两个码位边界索引（含行首/行尾），排序得 [ci_start, ci_end)。
    let a = rng.next_below(m + 1)
    let b = rng.next_below(m + 1)
    let ci_start = if a <= b { a } else { b }
    let ci_end = if a <= b { b } else { a }
    // 用 char_col 将码位边界换算为该编码下的合法列号。
    let start_col = char_col(line, enc, ci_start)
    let end_col = char_col(line, enc, ci_end)
    let range : Range = {
      start: { line: li, character: start_col },
      end: { line: li, character: end_col },
    }
    // 替换文本：0..3 个码位（取自码位池，不含 '\n'）。
    let rl = rng.next_below(4)
    let repl : Array[Int] = []
    let mut k = 0
    while k < rl {
      repl.push(gen_code_point(rng))
      k = k + 1
    }
    changes.push({ range: Some(range), text: cps_line_to_text(repl) })
    // 独立参照切割：原地更新行结构。
    splice_line(lines, li, ci_start, ci_end, repl)
    c = c + 1
  }
  let expected = build_text(lines)
  (text0, enc, changes, expected)
}

///|
/// 样本生成器（封装为 @infra_pbt.Gen）。
fn gen_sync_samples() -> @infra_pbt.Gen[
  (String, PositionEncoding, Array[ContentChange], String),
] {
  @infra_pbt.Gen::new(fn(rng) { gen_sync_sample(rng) })
}

// ---------------------------------------------------------------------------
// 属性测试（Property 5）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 5: 增量与全量等价
///
/// 对任意由生成器产出的（初始文本, 合法增量变更序列）对：
///   * 增量应用 `inc = apply_changes(text0, changes, enc)` 必为 `Ok`（生成的变更
///     范围均为合法码位边界），且与独立参照终文本 `expected` 逐字符相等；
///   * 全量替换 `full = apply_changes(text0, [{ range: None, text: inc }], enc)`
///     必为 `Ok` 且与 `inc` 逐字符相等（增量＝全量等价核心）；
///   * 诊断投影：`analyze(inc).diagnostics == analyze(full).diagnostics`
///     （Requirement 9.3）。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 3.2, 3.4, 3.6, 9.3**
test "Feature: lsp, Property 5: incremental and full document sync are equivalent (text and diagnostics)" {
  let uri = "file:///prop5.dsl"
  let ok = @infra_pbt.holds_for_all(gen_sync_samples(), fn(sample) {
    let (text0, enc, changes, expected) = sample
    match apply_changes(text0, changes, enc) {
      // 合法增量变更必应用成功。
      Err(_) => false
      Ok(inc) =>
        // 增量结果须等于独立参照终文本（真实增量语义校验，非平凡）。
        if inc != expected {
          false
        } else {
          // 以增量结果做全量替换，验证增量＝全量逐字符等价及其诊断投影。
          match apply_changes(text0, [{ range: None, text: inc }], enc) {
            Err(_) => false
            Ok(full) =>
              full == inc &&
              analyze({ uri, text: inc }).diagnostics ==
              analyze({ uri, text: full }).diagnostics
          }
        }
    }
  })
  assert_true(ok)
}
