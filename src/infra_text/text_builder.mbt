// text_builder.mbt —— 共享高效文本构建工具 `TextBuilder`。
//
// 设计依据（production-hardening/design.md §「Shared_Text_Builder 设计」）：
//
//   pub struct TextBuilder {
//     mut chunks   : Array[String]   // 已追加片段，物化时一次性 join
//     mut char_buf : Array[Char]     // 字符级追加缓冲，延迟合并到 chunks
//     mut total_len: Int             // 已追加字符总数（O(1) 维护）
//   }
//
// 复杂度目标：
//   * `push_char` / `push_str`：摊还 O(1)（仅向数组 push 并累加计数）；
//   * `build`：O(总输出长度)（先 flush 字符缓冲，再一次性 join 片段）。
//
// 关键不变量（Requirement 1）：
//   * AC1/AC3：`build()` 结果与等价顺序 `+` 拼接逐字符相等；
//   * AC2：依次追加 N 个片段的总时间对总输出长度呈线性；
//   * AC4：`build` 不清空内部状态，物化后继续 `push_*` 再次 `build`，
//     结果含先前与新追加的全部片段且顺序保持。

///|
/// 字符缓冲区的默认预留容量。
///
/// 命名常量，避免散落的 magic number；用于 `new` 时初始化字符缓冲，
/// 在多数小规模追加场景下减少底层数组扩容次数。
let default_char_capacity : Int = 16

///|
/// 高效文本构建器（Shared_Text_Builder）。
///
/// 以 `Array[String]` 收集已追加的字符串片段，物化时一次性 join；字符级
/// 追加先进入 `char_buf`，在 `push_str` 或 `build` 时折叠为单个 `String`
/// 片段并入 `chunks`，从而避免「每字符一次装箱 / 拼接」的开销。
///
/// 该结构以可变字段维护内部缓冲，追加操作就地更新，摊还 O(1)。
pub struct TextBuilder {
  // `chunks` 与 `char_buf` 仅就地 push / clear，不整体重绑定，故无需 `mut`；
  // `total_len` 需以 `mut` 维护 O(1) 累计计数。
  chunks : Array[String]
  char_buf : Array[Char]
  mut total_len : Int
}

///|
/// 创建一个空的 `TextBuilder`。
///
/// 初始 `chunks` 为空、`char_buf` 预留 `default_char_capacity` 容量、
/// `total_len` 为 0。
pub fn TextBuilder::new() -> TextBuilder {
  {
    chunks: [],
    char_buf: Array::new(capacity=default_char_capacity),
    total_len: 0,
  }
}

///|
/// 以预留的片段容量创建一个空的 `TextBuilder`。
///
/// `capacity` 为对 `chunks`（片段数组）预留的容量提示；负值按 0 处理。
/// 字符缓冲仍使用 `default_char_capacity` 初始化。预留容量仅为性能优化，
/// 不影响任何可观测的构建结果。
pub fn TextBuilder::with_capacity(capacity : Int) -> TextBuilder {
  let cap = if capacity < 0 { 0 } else { capacity }
  {
    chunks: Array::new(capacity=cap),
    char_buf: Array::new(capacity=default_char_capacity),
    total_len: 0,
  }
}

///|
/// 将字符缓冲 `char_buf` 折叠为单个字符串片段并入 `chunks`，随后清空
/// 字符缓冲。
///
/// 这是内部辅助：仅在缓冲非空时执行，保证 `build` 物化前所有字符级追加
/// 都已按顺序并入 `chunks`。折叠代价与缓冲长度成正比，跨多次 flush 的
/// 总代价对追加字符总数呈线性。
fn TextBuilder::flush_char_buf(self : TextBuilder) -> Unit {
  if self.char_buf.length() == 0 {
    return
  }
  let sb = StringBuilder::new()
  for c in self.char_buf {
    sb.write_char(c)
  }
  self.chunks.push(sb.to_string())
  // 清空字符缓冲，复用同一个对象避免重复分配。
  self.char_buf.clear()
}

///|
/// 追加单个字符。
///
/// 字符先进入 `char_buf`（摊还 O(1)），延迟到 `push_str` 或 `build` 时再
/// 折叠为字符串片段。`total_len` 同步累加。
pub fn TextBuilder::push_char(self : TextBuilder, c : Char) -> Unit {
  self.char_buf.push(c)
  self.total_len += 1
}

///|
/// 追加一个字符串片段。
///
/// 为保证顺序正确，先把待决的字符缓冲折叠并入 `chunks`，再追加本片段。
/// 空串不增加任何片段也不改变长度。追加本身为摊还 O(1)。
pub fn TextBuilder::push_str(self : TextBuilder, s : String) -> Unit {
  if s.length() == 0 {
    // 仍需保证：若此前有字符缓冲，顺序语义不受影响。空串不贡献长度，
    // 也无需立即 flush（flush 会在下次非空片段或 build 时发生）。
    return
  }
  self.flush_char_buf()
  self.chunks.push(s)
  self.total_len += s.length()
}

///|
/// 返回当前已追加的字符总数。
///
/// 该值由各追加操作以 O(1) 维护，等于物化结果 `build()` 的长度。
pub fn TextBuilder::len(self : TextBuilder) -> Int {
  self.total_len
}

///|
/// 判断构建器当前是否为空（尚未追加任何字符）。
pub fn TextBuilder::is_empty(self : TextBuilder) -> Bool {
  self.total_len == 0
}

///|
/// 物化为最终字符串。
///
/// 先把待决字符缓冲折叠并入 `chunks`，再以空分隔符 join 全部片段，结果
/// 与等价顺序 `+` 拼接逐字符相等（AC1/AC3）。
///
/// 重要不变量（AC4）：`build` **不**清空内部状态。flush 后 `char_buf`
/// 已并入 `chunks`，因此后续可继续 `push_*`，再次 `build` 时将包含先前与
/// 新追加的全部片段且顺序保持。
pub fn TextBuilder::build(self : TextBuilder) -> String {
  self.flush_char_buf()
  self.chunks.join("")
}

///|
/// 清空全部缓冲以复用该构建器。
///
/// 清空后 `chunks`、`char_buf` 均为空，`total_len` 归零，等价于一个全新的
/// `TextBuilder`。与 `build` 不同，`reset` 会丢弃全部已追加内容。
pub fn TextBuilder::reset(self : TextBuilder) -> Unit {
  self.chunks.clear()
  self.char_buf.clear()
  self.total_len = 0
}
