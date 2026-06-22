// ascii.mbt —— 文档注释中的 ASCII 网格可视化（方向 6 · R20.2/R20.3）。
//
// 设计依据（design.md §6.2「Ascii_Visualization 规范」/ Requirement 20）：
//   * 以精确结构体 `AsciiGrid` 表示「行列规模 + 障碍位图 + 起点 + 终点 +
//     路径序列」，禁止用字符串模拟结构化数据（R22.6）。
//   * `render_ascii()` 将网格渲染为「网格区域 + 图例」两段式 ASCII 文本：
//     网格区域仅使用 5 个互异单字符 `S`/`G`/`#`/`*`/`.`（R20.2），图例说明各
//     字符含义。
//   * 当 `path` 为空（无可行路径）时，输出省略路径字符 `*` 并在图例中标注
//     「无可行路径」（R20.3）。
//   * 文本构建统一经 `@infra_text.TextBuilder` 顺序追加，禁止在循环内做字符串
//     `+` 拼接（R19.4 / R22.4）；渲染耗时随单元格数 O(rows·cols) 线性增长。

///|
/// 起点单元格字符（5 个互异单字符之一 · R20.2）。
let char_start : Char = 'S'

///|
/// 终点单元格字符（5 个互异单字符之一 · R20.2）。
let char_goal : Char = 'G'

///|
/// 障碍单元格字符（5 个互异单字符之一 · R20.2）。
let char_blocked : Char = '#'

///|
/// 路径单元格字符（5 个互异单字符之一 · R20.2）；`path` 为空时不出现（R20.3）。
let char_path : Char = '*'

///|
/// 空闲单元格字符（5 个互异单字符之一 · R20.2）。
let char_empty : Char = '.'

///|
/// 行分隔符；同时用于网格区域与图例之间的空行分隔。
let row_separator : Char = '\n'

///|
/// 图例前缀标签。
let legend_label : String = "图例："

///|
/// 图例条目：起点（尾随空格分隔下一条目）。
let legend_item_start : String = "S=起点 "

///|
/// 图例条目：终点（尾随空格分隔下一条目）。
let legend_item_goal : String = "G=终点 "

///|
/// 图例条目：障碍（尾随空格分隔下一条目）。
let legend_item_blocked : String = "#=障碍 "

///|
/// 图例条目：路径（尾随空格分隔下一条目）；仅在存在可行路径时追加（R20.3）。
let legend_item_path : String = "*=路径 "

///|
/// 图例条目：空闲单元格。
let legend_item_empty : String = ".=空闲"

///|
/// 无可行路径时在图例中追加的标注（R20.3）。
let legend_no_path : String = "（无可行路径）"

///|
/// ASCII 网格可视化模型（精确结构体，禁止字符串模拟结构 · R22.6）。
///
/// 字段语义：
/// - `rows` / `cols`：网格行数与列数（典型示意规模 3×3–20×20 · R20.1）。
/// - `blocked`：行优先排布的障碍位图，长度应为 `rows * cols`；`blocked[r*cols+c]`
///   为 `true` 表示该单元格为障碍。
/// - `start` / `goal`：起点与终点的行优先线性索引（`r * cols + c`）。
/// - `path`：从起点到终点的单元格索引序列；**空数组表示无可行路径**，此时
///   渲染省略路径字符并在图例标注「无可行路径」（R20.3）。
pub(all) struct AsciiGrid {
  rows : Int
  cols : Int
  blocked : Array[Bool]
  start : Int
  goal : Int
  path : Array[Int]
}

///|
/// 判断线性索引 `idx` 是否落在 `[0, len)` 区间内（用于安全的位图 / 数组访问）。
fn in_bounds(idx : Int, len : Int) -> Bool {
  idx >= 0 && idx < len
}

///|
/// 计算单个单元格应渲染的字符；起点 / 终点优先于路径字符显示（R20.2）。
///
/// 优先级（从高到低）：起点 `S` → 终点 `G` → 路径 `*` → 障碍 `#` → 空闲 `.`。
/// 所有数组访问均先做边界检查，确保畸形输入（越界索引）不触发任何 panic。
fn cell_char(grid : AsciiGrid, on_path : Array[Bool], idx : Int) -> Char {
  if idx == grid.start {
    char_start
  } else if idx == grid.goal {
    char_goal
  } else if in_bounds(idx, on_path.length()) && on_path[idx] {
    char_path
  } else if in_bounds(idx, grid.blocked.length()) && grid.blocked[idx] {
    char_blocked
  } else {
    char_empty
  }
}

///|
/// 向构建器追加图例段；`has_path` 为假时省略路径字符并标注「无可行路径」（R20.3）。
///
/// 全程经 `TextBuilder` 顺序追加，不做循环内字符串 `+` 拼接（R19.4）。
fn append_legend(tb : @infra_text.TextBuilder, has_path : Bool) -> Unit {
  tb.push_str(legend_label)
  tb.push_str(legend_item_start)
  tb.push_str(legend_item_goal)
  tb.push_str(legend_item_blocked)
  // 仅当存在可行路径时才纳入路径字符 `*`（R20.3：无路径则全输出不含 `*`）。
  if has_path {
    tb.push_str(legend_item_path)
  }
  tb.push_str(legend_item_empty)
  if !has_path {
    tb.push_str(legend_no_path)
  }
}

///|
/// 将 `AsciiGrid` 渲染为带图例的 ASCII 文本（R20.2/R20.3）。
///
/// 输出形如（3×3，存在可行路径）：
/// ```text
/// S.#
/// .*.
/// #.G
///
/// 图例：S=起点 G=终点 #=障碍 *=路径 .=空闲
/// ```
///
/// 行为约定：
/// - **5 个互异单字符**：网格区域逐单元格渲染为 `S`/`G`/`#`/`*`/`.` 之一，
///   行间以换行分隔，单元格之间无额外间隔字符（R20.2）。
/// - **起点 / 终点优先**：当某单元格同时命中起点 / 终点与路径时，优先显示
///   起点 / 终点字符（R20.2）。
/// - **无可行路径**：`path` 为空时整段输出不含路径字符 `*`，且图例追加
///   「无可行路径」标注（R20.3）。
/// - **O(rows·cols) 线性 + 无循环内拼接**：统一经 `TextBuilder` 顺序追加，
///   末尾单次 `build()` 物化，循环内不使用字符串 `+`（R19.4）。
pub fn render_ascii(grid : AsciiGrid) -> String {
  let cell_count = grid.rows * grid.cols
  // 路径位图：以 O(path) 标记落在合法范围内的路径单元，越界索引被忽略。
  let buf_len = if cell_count > 0 { cell_count } else { 0 }
  let on_path : Array[Bool] = Array::make(buf_len, false)
  for k = 0; k < grid.path.length(); k = k + 1 {
    let p = grid.path[k]
    if in_bounds(p, buf_len) {
      on_path[p] = true
    }
  }
  let has_path = grid.path.length() > 0
  let tb = @infra_text.TextBuilder::new()
  // 网格区域：逐行逐列追加单元格字符，每行末尾追加换行。
  for r = 0; r < grid.rows; r = r + 1 {
    for c = 0; c < grid.cols; c = c + 1 {
      let idx = r * grid.cols + c
      tb.push_char(cell_char(grid, on_path, idx))
    }
    tb.push_char(row_separator)
  }
  // 空行分隔后追加图例段。
  tb.push_char(row_separator)
  append_legend(tb, has_path)
  tb.build()
}
