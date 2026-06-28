// prop_position_offset_test.mbt —— Position↔offset 往返属性测试（任务 6.3，Property 6）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 6「Position↔offset 往返」：
//
//   *对任意* 由生成器产出的（文本, 位置编码, 文本内有效位置）三元组 (text, enc, p)，
//   先把 `p` 经 `position_to_offset` 换算为该编码下的线性 offset，再经
//   `offset_to_position` 换算回 Position，所得结果与原 `p` 相等：
//       offset_to_position(text, position_to_offset(text, p, enc), enc) == Some(p)
//
// **Validates: Requirements 4.2, 4.3, 4.6**
//
// ── 「文本内有效位置」生成策略（保证属性非平凡且可靠）──────────────────────
// 本文件为黑盒测试，仅依赖 position_encoding.mbt 的公开 API（`code_units` /
// `position_to_offset` / `offset_to_position` / `Position` / `PositionEncoding`），
// 不触碰其私有的 `to_lines` / `char_to_index` 等内部工具。为确保每个生成的
// Position 都**恰好落在码位边界上**（而非多码元字符中间，否则换算返回 None 使
// 属性平凡成立），生成器**自行构造文本的码位结构**：
//   1. 随机生成若干「行」，每行是一段码位（`Int`）序列（不含 '\n'）；
//   2. 由这些行用 '\n' 拼接出文本 `text`（与 position_encoding 的行模型一致）；
//   3. 随机选一行 `li` 与一个**码位边界索引** `ci`（0..该行码位数，含行首与行尾）；
//   4. 用 `code_units` 在所选编码下累计该行前 `ci` 个码位的码元数，得到列号
//      `character`——由此 Position {line: li, character} 必为合法码位边界。
// 码位池刻意覆盖：ASCII、拉丁补充（é，UTF-8 双字节）、CJK（中/文，UTF-8 三字节、
// BMP 内）、emoji（😀/💩，BMP 外、UTF-16 代理对、UTF-8 四字节）、CJK 扩展 B
// （𠀀，BMP 外）；再随机插入多行。故属性真正覆盖含多字节 / 代理对 / 多行的
// 有效位置往返，而非仅 ASCII 单行平凡样本。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。

// ---------------------------------------------------------------------------
// 随机生成器（文本码位结构 + 编码 + 文本内有效位置）
// ---------------------------------------------------------------------------

///|
/// 码位池（均不含 '\n'/U+000A），覆盖单 / 多码元各类字符以保证属性非平凡：
///   * ASCII：'a' 'b' ' ' '=' '0'
///   * 拉丁补充：'é'(U+00E9，UTF-8 双字节、BMP 内)
///   * CJK：'中'(U+4E2D) '文'(U+6587)（UTF-8 三字节、BMP 内）
///   * emoji：'😀'(U+1F600) '💩'(U+1F4A9)（BMP 外、UTF-16 代理对、UTF-8 四字节）
///   * CJK 扩展 B：'𠀀'(U+20000)（BMP 外）
let code_point_pool : Array[Int] = [
  0x61, 0x62, 0x20, 0x3D, 0x30, 0x00E9, 0x4E2D, 0x6587, 0x1F600, 0x1F4A9, 0x20000,
]

///|
/// 随机取一个码位（来自 `code_point_pool`）。
fn gen_code_point(rng : @infra_pbt.Rng) -> Int {
  code_point_pool[rng.next_below(code_point_pool.length())]
}

///|
/// 随机生成「行」序列：1..4 行，每行 0..6 个码位（不含 '\n'）。
fn gen_lines(rng : @infra_pbt.Rng) -> Array[Array[Int]] {
  let n_lines = rng.next_range(1, 4)
  let lines : Array[Array[Int]] = []
  let mut l = 0
  while l < n_lines {
    let len = rng.next_below(7) // 0..6
    let line : Array[Int] = []
    let mut k = 0
    while k < len {
      line.push(gen_code_point(rng))
      k = k + 1
    }
    lines.push(line)
    l = l + 1
  }
  lines
}

///|
/// 由「行」序列用 '\n' 拼接出文本字符串（与 position_encoding 的行模型一致）。
fn build_text(lines : Array[Array[Int]]) -> String {
  let mut s = ""
  let mut li = 0
  while li < lines.length() {
    if li > 0 {
      s = s + "\n"
    }
    for cp in lines[li] {
      s = s + Int::unsafe_to_char(cp).to_string()
    }
    li = li + 1
  }
  s
}

///|
/// 在编码 `enc` 下，所选行前 `ci` 个码位的码元数之和，即该码位边界对应的列号。
fn char_col(line : Array[Int], enc : PositionEncoding, ci : Int) -> Int {
  let mut acc = 0
  let mut i = 0
  while i < ci {
    acc = acc + code_units(line[i], enc)
    i = i + 1
  }
  acc
}

///|
/// 随机取一个位置编码（三选一）。
fn gen_encoding(rng : @infra_pbt.Rng) -> PositionEncoding {
  match rng.next_below(3) {
    0 => Utf16
    1 => Utf8
    _ => Utf32
  }
}

///|
/// 生成三元组（文本, 位置编码, 文本内有效位置）。位置由「码位边界索引」构造，
/// 故必为合法边界（落在行首 / 行尾 / 两码位之间，绝不在多码元字符中间）。
fn gen_text_enc_pos(
  rng : @infra_pbt.Rng,
) -> (String, PositionEncoding, Position) {
  let lines = gen_lines(rng)
  let text = build_text(lines)
  let enc = gen_encoding(rng)
  let li = rng.next_below(lines.length())
  let line = lines[li]
  let ci = rng.next_below(line.length() + 1) // 0..码位数（含行尾）
  let character = char_col(line, enc, ci)
  (text, enc, { line: li, character })
}

///|
/// （文本, 编码, 有效位置）生成器（封装为 @infra_pbt.Gen）。
fn gen_samples() -> @infra_pbt.Gen[(String, PositionEncoding, Position)] {
  @infra_pbt.Gen::new(fn(rng) { gen_text_enc_pos(rng) })
}

// ---------------------------------------------------------------------------
// 属性测试（Property 6）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 6: Position↔offset 往返
///
/// 对任意由生成器产出的（文本, 位置编码, 文本内有效位置）三元组：
///   * `position_to_offset(text, p, enc)` 必为 `Some(off)`（生成的 Position 落在
///     合法码位边界上，不应换算失败）；
///   * `offset_to_position(text, off, enc)` 必等于 `Some(p)`（往返不变）。
/// 二者合起来即 `offset_to_position(position_to_offset(p)) == p`。
/// （`Position` 仅派生 Eq、无 Show，故谓词以 `== Some(p)` 返回 Bool。）
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 4.2, 4.3, 4.6**
test "Feature: lsp, Property 6: position/offset round-trip holds for valid positions across encodings" {
  let ok = @infra_pbt.holds_for_all(gen_samples(), fn(triple) {
    let (text, enc, p) = triple
    match position_to_offset(text, p, enc) {
      // 生成的 Position 必为合法边界，position_to_offset 不应返回 None。
      None => false
      // 往返回到原 Position（Property 6 核心断言）。
      Some(off) => offset_to_position(text, off, enc) == Some(p)
    }
  })
  assert_true(ok)
}
