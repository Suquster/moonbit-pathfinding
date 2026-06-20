// position_encoding.mbt —— 位置编码协商与 Position↔offset 坐标换算
// （旗舰深化，任务 6.1 旁路新增）。
//
// paper-to-code 追溯（design.md §3.4 / Requirement 4）：
//   * LSP 规范 `PositionEncodingKind`：位置的 `character` 列号单位由位置编码决定，
//     LSP 默认 `UTF-16`，可协商为 `UTF-8` / `UTF-32`。
//     <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#positionEncodingKind>
//   * Unicode 码元约定（单个码位 cp 在各编码下占用的「码元（code unit）」数）：
//       - UTF-16：基本多文种平面（BMP，cp ≤ 0xFFFF）= 1 个 16-bit 码元；
//                 BMP 外（cp ≥ 0x10000，需代理对）= 2 个码元。
//       - UTF-8 ：cp ≤ 0x7F → 1 字节；≤ 0x7FF → 2；≤ 0xFFFF → 3；否则 4 字节。
//       - UTF-32：恒为 1 个码元（每码位 1）。
//
// 实现策略（务必稳健，design.md §3.4「关键实现策略」）：
//   为保证三后端（wasm-gc / js / native）逐位一致，且 Position↔offset 往返与
//   跨编码换算往返严格成立，本模块**显式按 Unicode 码位计算**，不依赖任何后端
//   字符串长度语义。已验证 MoonBit `for c in text` 按 **Unicode 码位**迭代
//   （BMP 外字符给出单个 `Char`，`c.to_int()` 得真实码位，如 emoji = 0x1F600），
//   故可直接遍历码位序列计量。
//
//   坐标模型（自洽且可往返）：
//     1. 文本按 '\n'（U+000A）拆分为若干「行」，每行是一段码位序列（不含 '\n'）。
//        '\n' 在三种编码下均计 1 个码元，作为行分隔贡献。
//     2. `Position.character` 为「该行内、目标码位边界之前所有码位的 code_units 之和」
//        （单位随编码而变）。仅落在码位边界上的 character 有效。
//     3. 线性 `offset` 以「编码码元」为单位线性遍历整个文本（含换行符）：
//          offset(line, character) = Σ_{i<line}(line_code_units(行 i) + 1) + character
//        其中 +1 为该行末尾 '\n' 的码元贡献。`offset_to_position` 为其逆。
//        因相邻行的「行尾位置」与「下一行行首位置」相差恰为 1（换行符），故每个
//        合法 offset 唯一对应一个码位边界，往返成立（Property 6）。
//   越界（line 超行数 / character 超该行码元长度或落在码元中间 / offset 超总码元数
//   或落在码元中间）一律返回 `None`。
//
// 跨编码换算（convert_position）以「行内第几个码位（charIndex，编码无关）」为中介：
//   先把源编码 Position 解析为 (line, charIndex)，再用目标编码重新计量列号。
//   由此 convert(convert(p, A→B), B→A) == p（Property 7）。代理对字符在 UTF-16
//   计 2、UTF-8 计 4、UTF-32 计 1，三者指向同一字符边界。

///|
/// 位置编码种类（LSP `PositionEncodingKind`）。
pub(all) enum PositionEncoding {
  Utf16 // LSP 默认：BMP 内 1 码元 / BMP 外 2 码元
  Utf8 // 按 UTF-8 字节数：1..4
  Utf32 // 按 Unicode 码位：恒 1
} derive(Eq, Show)

///|
/// 单个码位 `cp` 在编码 `enc` 下对列号 / offset 的贡献（码元数）。
/// （Requirement 4.4）
pub fn code_units(cp : Int, enc : PositionEncoding) -> Int {
  match enc {
    Utf16 => if cp <= 0xFFFF { 1 } else { 2 }
    Utf8 =>
      if cp <= 0x7F {
        1
      } else if cp <= 0x7FF {
        2
      } else if cp <= 0xFFFF {
        3
      } else {
        4
      }
    Utf32 => 1
  }
}

///|
/// 位置编码协商（Requirement 4.1）：服务端支持全部三种编码，取客户端声明列表中
/// 服务端也支持的**首个**编码为协商结果；客户端无声明（空列表）时回退到 `Utf16`。
pub fn negotiate_encoding(client : Array[PositionEncoding]) -> PositionEncoding {
  for enc in client {
    // 服务端支持全部三种编码，故客户端列出的首个即为共同支持的首选。
    match enc {
      Utf16 | Utf8 | Utf32 => return enc
    }
  }
  Utf16
}

// ───────────────────────────── 内部码位 / 行工具 ─────────────────────────

///|
/// 将文本拆分为「行」序列，每行为一段码位（`Int`）序列，按 '\n'（U+000A）分隔
/// （'\n' 本身不计入任何行）。空文本得到单个空行 `[[]]`。
fn to_lines(text : String) -> Array[Array[Int]] {
  let lines : Array[Array[Int]] = []
  let mut cur : Array[Int] = []
  for c in text {
    let cp = c.to_int()
    if cp == 0x0A {
      lines.push(cur)
      cur = []
    } else {
      cur.push(cp)
    }
  }
  lines.push(cur)
  lines
}

///|
/// 一行（码位序列）在编码 `enc` 下的总码元数。
fn line_units(line : Array[Int], enc : PositionEncoding) -> Int {
  let mut sum = 0
  for cp in line {
    sum = sum + code_units(cp, enc)
  }
  sum
}

///|
/// 把行内列号 `character`（`enc` 码元单位）解析为「行内第几个码位」charIndex。
/// 仅当 `character` 恰好落在某码位边界上（含行首 0 与行尾）时返回 `Some(idx)`；
/// 落在多码元字符中间或超出行长返回 `None`。
fn char_to_index(
  line : Array[Int],
  enc : PositionEncoding,
  character : Int,
) -> Int? {
  if character < 0 {
    return None
  }
  if character == 0 {
    return Some(0)
  }
  let mut acc = 0
  let mut idx = 0
  for cp in line {
    acc = acc + code_units(cp, enc)
    idx = idx + 1
    if acc == character {
      return Some(idx)
    }
    if acc > character {
      return None // 落在多码元字符中间
    }
  }
  None // character 超出该行码元长度
}

///|
/// 把「行内第几个码位」charIndex 转回行内列号 `character`（`enc` 码元单位）。
/// `idx` 超出行内码位数返回 `None`。
fn index_to_char(line : Array[Int], enc : PositionEncoding, idx : Int) -> Int? {
  if idx < 0 || idx > line.length() {
    return None
  }
  let mut acc = 0
  let mut i = 0
  for cp in line {
    if i == idx {
      break
    }
    acc = acc + code_units(cp, enc)
    i = i + 1
  }
  Some(acc)
}

// ───────────────────────────── Position ↔ offset ─────────────────────────

///|
/// 将 `Position` 换算为编码 `enc` 下的线性 `offset`（码元单位）（Requirement 4.2）。
/// 越界 line 或非码位边界的 character 返回 `None`。
pub fn position_to_offset(
  text : String,
  pos : Position,
  enc : PositionEncoding,
) -> Int? {
  let lines = to_lines(text)
  if pos.line < 0 || pos.line >= lines.length() {
    return None
  }
  // 校验 character 落在码位边界上。
  match char_to_index(lines[pos.line], enc, pos.character) {
    None => None
    Some(_) => {
      let mut prefix = 0
      let mut i = 0
      while i < pos.line {
        prefix = prefix + line_units(lines[i], enc) + 1 // +1 为该行 '\n'
        i = i + 1
      }
      Some(prefix + pos.character)
    }
  }
}

///|
/// 将编码 `enc` 下的线性 `offset` 换算为 `Position`（Requirement 4.3）。
/// 越界或非码位边界的 offset 返回 `None`。
pub fn offset_to_position(
  text : String,
  offset : Int,
  enc : PositionEncoding,
) -> Position? {
  if offset < 0 {
    return None
  }
  let lines = to_lines(text)
  let mut start = 0
  let mut line = 0
  while line < lines.length() {
    let lu = line_units(lines[line], enc)
    // 本行的合法位置占据 offset 区间 [start, start + lu]（行尾含）。
    if offset <= start + lu {
      let character = offset - start
      match char_to_index(lines[line], enc, character) {
        None => return None // 落在多码元字符中间
        Some(_) => return Some({ line, character })
      }
    }
    start = start + lu + 1 // +1 跳过该行 '\n'
    line = line + 1
  }
  None // offset 超出文本总码元数
}

///|
/// 将同一文本中的同一字符边界在两种编码间换算（Requirement 4.5）：
/// 先用源编码 `from` 把 `pos` 解析为行内码位索引，再用目标编码 `to` 重新计量列号。
/// 越界或非码位边界返回 `None`。
pub fn convert_position(
  text : String,
  pos : Position,
  from~ : PositionEncoding,
  to~ : PositionEncoding,
) -> Position? {
  let lines = to_lines(text)
  if pos.line < 0 || pos.line >= lines.length() {
    return None
  }
  let line = lines[pos.line]
  match char_to_index(line, from, pos.character) {
    None => None
    Some(idx) =>
      match index_to_char(line, to, idx) {
        None => None
        Some(ch) => Some({ line: pos.line, character: ch })
      }
  }
}
