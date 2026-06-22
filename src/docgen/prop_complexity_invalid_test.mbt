// Feature: championship-v1-upgrade, Property 31: 元数据缺失/空字段时生成失败且不部分写入
//
// 本文件实现 Property 31（设计文档 §「Property 31: 元数据缺失/空字段时生成
// 失败且不部分写入」/ Requirement 19.5）的属性测试：
//   * 对任意「多数字段非空」的随机 AlgoMeta 数组，随机挑选一条记录的随机
//     一个必填字段置为空字符串 ""，则 complexity_table 必返回
//     Err(@graph.PathError::InvalidArgument(...))（可 pattern match 验证变体）。
//   * 对照：全部字段非空时返回 Ok。
//   * 「不部分写入」：complexity_table 是纯函数返回 Result，Err 即不返回任何
//     表字符串（天然满足）；断言中确认返回的是 Err 分支而非 Ok。
//
// 复用共享 PBT 包 @infra_pbt 的 Gen / Rng / holds_for_all 模板，显式迭代
// 100 次（满足 Requirement 11.3 基线 ≥100）。

///|
/// 生成一段「保证非空」的随机算法元数据文本（长度 1..=8 的字母串）。
///
/// 用随机种子 rng 驱动，确保对照组的字段不会意外为空，从而把「失败」唯一
/// 归因于被显式置空的那个字段。
fn ci_nonblank_text(rng : @infra_pbt.Rng) -> String {
  // 长度至少 1，避免空串；上限 8 控制生成规模。
  let len = rng.next_below(8) + 1
  let buf = @infra_text.TextBuilder::new()
  for i = 0; i < len; i = i + 1 {
    // 在 'a'..='z' 范围内取字符（共 26 个），保证为可见非空字符。
    let code = 0x61 + rng.next_below(26)
    buf.push_char(code.unsafe_to_char())
  }
  buf.build()
}

///|
/// 生成一条全部字段非空的随机 AlgoMeta。
fn ci_random_meta(rng : @infra_pbt.Rng) -> AlgoMeta {
  {
    name: ci_nonblank_text(rng),
    worst_time: ci_nonblank_text(rng),
    avg_time: ci_nonblank_text(rng),
    space: ci_nonblank_text(rng),
    applicability: ci_nonblank_text(rng),
  }
}

///|
/// 返回把第 `field` 个必填字段置为空字符串 "" 后的元数据副本。
///
/// field 取值 0..=4 分别对应 name / worst_time / avg_time / space /
/// applicability。AlgoMeta 字段不可变，故构造一条新记录返回。
fn ci_blank_field_at(m : AlgoMeta, field : Int) -> AlgoMeta {
  match field {
    0 => { ..m, name: "" }
    1 => { ..m, worst_time: "" }
    2 => { ..m, avg_time: "" }
    3 => { ..m, space: "" }
    _ => { ..m, applicability: "" }
  }
}

///|
/// 生成一个「多数字段非空，但恰有一条记录的一个字段被置空」的元数据数组。
///
/// 返回数组长度 1..=6；先全部填充非空字段，再随机挑选一条记录的随机一个
/// 字段置空，确保数组中至少存在一个空必填字段（触发失败的最小条件）。
fn ci_gen_one_blank(rng : @infra_pbt.Rng) -> Array[AlgoMeta] {
  let n = rng.next_below(6) + 1
  let arr : Array[AlgoMeta] = []
  for i = 0; i < n; i = i + 1 {
    arr.push(ci_random_meta(rng))
  }
  // 随机挑选一条记录与一个字段置空。
  let victim = rng.next_below(n)
  let field = rng.next_below(5)
  arr[victim] = ci_blank_field_at(arr[victim], field)
  arr
}

///|
/// 生成一个「全部字段非空」的合法元数据数组（对照组），长度 1..=6。
fn ci_gen_all_nonblank(rng : @infra_pbt.Rng) -> Array[AlgoMeta] {
  let n = rng.next_below(6) + 1
  let arr : Array[AlgoMeta] = []
  for i = 0; i < n; i = i + 1 {
    arr.push(ci_random_meta(rng))
  }
  arr
}

///|
/// 判断 complexity_table 的返回是否为 @graph.PathError::InvalidArgument 变体。
///
/// 既验证「返回 Err 分支而非 Ok」（不部分写入），也验证错误变体精确为
/// InvalidArgument（R19.5 约定的失败语义）。
fn ci_is_invalid_argument_err(metas : Array[AlgoMeta]) -> Bool {
  match complexity_table(metas) {
    Err(@graph.PathError::InvalidArgument(_)) => true
    _ => false
  }
}

///|
/// Feature: championship-v1-upgrade, Property 31（确定性校验）：空字段触发 InvalidArgument
///
/// 对 5 个必填字段逐一置空，断言 complexity_table 均返回
/// Err(InvalidArgument(...))；同时验证全字段非空时返回 Ok。
///
/// **Validates: Requirements 19.5**
test "Feature: championship-v1-upgrade, Property 31: blank required field yields InvalidArgument (deterministic)" {
  let base : AlgoMeta = {
    name: "BFS",
    worst_time: "O(V + E)",
    avg_time: "O(V + E)",
    space: "O(V)",
    applicability: "无权图最短路",
  }
  // 全字段非空 → Ok（对照）。
  match complexity_table([base]) {
    Ok(_) => ()
    Err(_) => abort("complexity_table 对全字段非空元数据不应失败")
  }
  // 逐一置空 5 个字段 → 均返回 Err(InvalidArgument(...))。
  for field = 0; field < 5; field = field + 1 {
    let broken = ci_blank_field_at(base, field)
    assert_true(ci_is_invalid_argument_err([broken]))
  }
}

///|
/// Feature: championship-v1-upgrade, Property 31（属性·随机空字段必失败，≥100 迭代）
///
/// 对任意「多数字段非空、恰有一条记录的一个字段被置空」的随机元数据数组，
/// complexity_table 必返回 Err(@graph.PathError::InvalidArgument(...))，
/// 即不产出任何表字符串（不部分写入）。
///
/// **Validates: Requirements 19.5**
test "Feature: championship-v1-upgrade, Property 31: any blank field causes Err without partial write (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { ci_gen_one_blank(rng) })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(metas) { ci_is_invalid_argument_err(metas) },
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 31（属性·对照组全非空返回 Ok，≥100 迭代）
///
/// 对任意「全部字段非空」的随机元数据数组，complexity_table 必返回 Ok，
/// 与「空字段必失败」形成对照，确认失败唯一归因于空必填字段。
///
/// **Validates: Requirements 19.5**
test "Feature: championship-v1-upgrade, Property 31: all-nonblank metadata yields Ok (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { ci_gen_all_nonblank(rng) })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(metas) {
      match complexity_table(metas) {
        Ok(_) => true
        Err(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
