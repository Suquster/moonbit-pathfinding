// prop_cross_encoding_test.mbt —— 跨编码换算往返属性测试（任务 6.4，Property 7）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 7「跨编码换算往返」：
//
//   *对任意* 由生成器产出的（文本, 源编码 src, 目标编码 to, 文本内有效位置 p），
//   先把 `p` 从源编码 `src` 换算到目标编码 `to`，再从 `to` 换算回 `src`，所得
//   结果与原 `p` 相等：
//       let p2 = convert_position(text, p,  from=src, to=to)   // 必为 Some
//       convert_position(text, p2, from=to, to=src) == Some(p) // 往返不变
//
//   代理对（BMP 外字符，如 emoji 😀 / CJK 扩展 𠀀）在各编码下按规定码元计入
//   列号——UTF-16 计 2、UTF-8 计 4、UTF-32 计 1——但三者指向同一字符边界，
//   故 src→to→src 往返必回到原列号。code_point_pool（见 6.3 生成器）已含
//   emoji 与 CJK 扩展区码位，属性真正覆盖含多字节 / 代理对的跨编码换算。
//
// **Validates: Requirements 4.4, 4.5, 4.7**
//
// ── 生成策略 ────────────────────────────────────────────────────────────
// 本文件为黑盒测试，仅依赖 position_encoding.mbt 的公开 API（`convert_position` /
// `Position` / `PositionEncoding`），并**复用同包文件 prop_position_offset_test.mbt
// （任务 6.3）已定义的生成器与 helper**（`gen_text_enc_pos` / `gen_encoding` 等，
// 同包可见，不在此重定义以免重名冲突）。
//   1. 用 `gen_text_enc_pos(rng)` 得到 (text, src, p)——p 必落在合法码位边界上；
//   2. 再用 `gen_encoding(rng)` 随机取目标编码 `to`（允许 to == src，往返同样成立）；
//   3. 组合为四元组 (text, src, to, p)。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `holds_for_all` 模板（默认 `iters=100`，
// 满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。

// ---------------------------------------------------------------------------
// 随机生成器（文本码位结构 + 源编码 + 目标编码 + 文本内有效位置）
// ---------------------------------------------------------------------------

///|
/// 生成四元组（文本, 源编码 src, 目标编码 to, 文本内有效位置 p）。
/// 复用 6.3 的 `gen_text_enc_pos`（产出 text/src/p，p 必为合法码位边界），
/// 再用 6.3 的 `gen_encoding` 追加一个随机目标编码 `to`。
fn gen_cross_samples() -> @infra_pbt.Gen[
  (String, PositionEncoding, PositionEncoding, Position),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let (text, src, p) = gen_text_enc_pos(rng)
    let to = gen_encoding(rng)
    (text, src, to, p)
  })
}

// ---------------------------------------------------------------------------
// 属性测试（Property 7）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 7: 跨编码换算往返
///
/// 对任意由生成器产出的（文本, 源编码 src, 目标编码 to, 文本内有效位置 p）：
///   * `convert_position(text, p, from=src, to=to)` 必为 `Some(p2)`（生成的
///     Position 落在合法码位边界上，不应换算失败）；
///   * `convert_position(text, p2, from=to, to=src)` 必等于 `Some(p)`（往返不变）。
/// 二者合起来即 `convert(convert(p, src→to), to→src) == p`，且代理对字符在各编码
/// 下按 UTF-16=2 / UTF-8=4 / UTF-32=1 码元计列号、指向同一字符边界。
/// （`Position` 仅派生 Eq、无 Show，故谓词以 `== Some(p)` 返回 Bool。）
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 4.4, 4.5, 4.7**
test "Feature: lsp, Property 7: cross-encoding conversion round-trips for valid positions" {
  let ok = @infra_pbt.holds_for_all(gen_cross_samples(), fn(quad) {
    let (text, src, to, p) = quad
    match convert_position(text, p, from=src, to~) {
      // 生成的 Position 必为合法边界，src→to 换算不应返回 None。
      None => false
      // 再 to→src 换算回原 Position（Property 7 核心断言）。
      Some(p2) => convert_position(text, p2, from=to, to=src) == Some(p)
    }
  })
  assert_true(ok)
}
