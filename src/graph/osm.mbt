// osm.mbt —— OSM 路网子集解析与「数据缺失安全降级」加载器。
//
// 设计依据（design.md §「方向 2 · 2.6 CH/JPS/ALT 生产级升级」/ Requirement 8.7）：
//   `benches/osm/download.sh` 拉取真实路网子集并写出制表符分隔（TSV）的边表
//   （列：`src  dst  length_m`）。本模块负责把该文本解析为统一的
//   `@graph.CsrGraph[Double]`（压缩稀疏行），供 CH/JPS/ALT 正确性对拍与基准复用。
//
//   关键不变量（R8.7 · 降级而非中止）：
//     * 当 OSM 数据在执行环境中不可用（文件缺失 / 内容为空 / 解析失败）时，
//       加载器**不报错、不崩溃**，而是记录结构化缺失诊断并改用**合成路网**
//       （均匀代价网格）完成正确性验证，使整套基准/测试不因数据缺失而失败。
//
// 质量约束（项目 steering）：
//   * 全程 `///|` 块注释、中文说明；无 `abort`/`todo!`/`panic`/`unimplemented` 占位。
//   * 无 O(n²) 字符串拼接：行/字段切分与诊断构建统一走 `@infra_text.TextBuilder`，
//     绝不在循环体内使用字符串 `+` 累加。
//   * 以精确枚举/结构体表示结构化数据（`OsmDataSource` / `OsmLoadOutcome`），
//     不用字符串模拟结构化状态（R22.6）。
//   * 复用同包既有 `PathError`（path_error.mbt），不新增错误类型、不改既有公开签名。

///|
/// 网格回退的默认边数下界守卫：当调用方给出的回退维度非法（≤ 0）时，
/// 退化为该最小维度，保证合成图至少含一个节点、不产生空图。
let osm_min_fallback_dim : Int = 1

///|
/// 路网数据来源：精确区分「真实 OSM 子集」与「合成回退网格」两种互斥来源。
///
/// 以枚举（而非字符串标记）表示加载结果的数据出处（R22.6）：
///
/// - `RealOsm`：成功解析了非空的真实 OSM 路网子集。
/// - `SyntheticFallback`：OSM 数据缺失 / 为空 / 解析失败，已降级为合成网格。
///
/// 调用方可据此在基准报告中标注数据出处，使「真实路网」与「合成回退」的
/// 结果不被混淆（R8.7）。
pub(all) enum OsmDataSource {
  /// 来自真实 OSM 路网子集（解析成功且非空）。
  RealOsm
  /// 来自合成回退网格（数据缺失或解析失败时的安全降级）。
  SyntheticFallback
} derive(Eq, Debug)

///|
/// 路网加载结果：始终携带一张有效的 `CsrGraph[Double]` 与其来源/规模/诊断。
///
/// 字段：
///
/// - `graph`：最终可用于算法的 CSR 路网图（真实或合成，恒为有效图）。
/// - `source`：数据来源（`RealOsm` / `SyntheticFallback`）。
/// - `node_count` / `edge_count`：图的节点数与有向边数（便于报告记录图规模）。
/// - `diagnostic`：人类可读诊断串；真实数据记录规模，降级时记录缺失/失败原因。
///
/// 该结构由 `load_osm_or_synthetic` 产出，是「降级而非中止」语义的载体（R8.7）。
pub(all) struct OsmLoadOutcome {
  graph : CsrGraph[Double]
  source : OsmDataSource
  node_count : Int
  edge_count : Int
  diagnostic : String
}

///|
/// 判断字符是否为「字段内空白」（空格 / 制表符 / 回车），用于裁剪字段两端。
///
/// 不含换行 `\n`，因为换行已在按行切分阶段被消费。
fn osm_is_trim_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
/// 将字符串展开为 `Array[Char]`（按 Unicode 标量逐字符），便于随机访问。
///
/// `String` 的下标访问返回 UTF-16 码元（`UInt16`）而非 `Char`，故凡需按字符
/// 随机访问处统一先经本函数物化为字符数组，避免码元/字符语义混淆。
fn osm_chars(s : String) -> Array[Char] {
  let cs : Array[Char] = []
  for c in s {
    cs.push(c)
  }
  cs
}

///|
/// 裁剪字符串两端的空白（空格 / 制表符 / 回车），返回新字符串。
///
/// 先展开为字符数组，再一次线性扫描定位 `[lo, hi)` 区间并物化，不在循环内做
/// 字符串 `+` 拼接。
fn osm_trim(s : String) -> String {
  let cs = osm_chars(s)
  let n = cs.length()
  let mut lo = 0
  while lo < n && osm_is_trim_space(cs[lo]) {
    lo = lo + 1
  }
  let mut hi = n
  while hi > lo && osm_is_trim_space(cs[hi - 1]) {
    hi = hi - 1
  }
  let tb = @infra_text.TextBuilder::new()
  for i in lo..<hi {
    tb.push_char(cs[i])
  }
  tb.build()
}

///|
/// 返回字符串首字符（按 Unicode 标量）；空串返回 `None`。
fn osm_first_char(s : String) -> Char? {
  for c in s {
    return Some(c)
  }
  None
}

///|
/// 按换行符 `\n` 将文本切分为行序列（不含换行符本身；`\r` 留待字段裁剪处理）。
///
/// 每行经由独立的 `TextBuilder` 逐字符累积、行末一次性物化，故全程为
/// 摊还 O(1) 追加 + O(n) 物化，杜绝循环内字符串 `+` 拼接。
fn osm_split_lines(content : String) -> Array[String] {
  let lines : Array[String] = []
  let tb = @infra_text.TextBuilder::new()
  for c in content {
    if c == '\n' {
      lines.push(tb.build())
      tb.reset()
    } else {
      tb.push_char(c)
    }
  }
  // 收尾：最后一行（若文本不以换行结束，则其内容仍在缓冲中）。
  lines.push(tb.build())
  lines
}

///|
/// 按制表符 `\t` 将单行切分为字段序列，并对每个字段裁剪两端空白。
///
/// 与 `osm_split_lines` 同构：每字段独立缓冲、一次性物化，无循环内 `+` 拼接。
fn osm_split_fields(line : String) -> Array[String] {
  let fields : Array[String] = []
  let tb = @infra_text.TextBuilder::new()
  for c in line {
    if c == '\t' {
      fields.push(osm_trim(tb.build()))
      tb.reset()
    } else {
      tb.push_char(c)
    }
  }
  fields.push(osm_trim(tb.build()))
  fields
}

///|
/// 解析非负整数节点标识：仅接受非空、全为十进制数字的字符串，返回 `Some(值)`；
/// 任何非法形态（空串 / 含非数字字符 / 含符号）返回 `None`。
///
/// 不依赖外部解析器对前导符号/空白的宽松处理，确保「合法节点标识」判定严格、
/// 三后端一致；用于同时承担「是否像表头」的判定（表头字段非纯数字）。
fn osm_parse_node_id(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut acc = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    acc = acc * 10 + (c.to_int() - '0'.to_int())
  }
  Some(acc)
}

///|
/// 解析边权（米）为 `Double`：包装标准库 `@strconv.parse_double`，失败返回 `None`。
///
/// 接受形如 `100`、`100.0`、`1.5e3` 的十进制/科学计数表示（与 download.sh 写出的
/// `length_m` 列对齐）。
fn osm_parse_weight(s : String) -> Double? {
  Some(@string.parse_double(s)) catch {
    _ => None
  }
}

///|
/// 一条已校验的 OSM 有向边：源、目标（均为非负节点标识）、非负边权（米）。
priv struct OsmEdge {
  src : Int
  dst : Int
  weight : Double
}

///|
/// 由已校验的边集合（按 `(src, dst)` 排序）构造 `CsrGraph[Double]`。
///
/// `n` 为节点数（节点标识 `0..n-1`）；边已在调用方按源、目标升序排序，故逐边
/// 推进 `row_ptr`：当源跨越到新行时补齐中间空行的偏移，保证 `row_ptr` 长度恰为
/// `n + 1` 且单调不减。全程仅向新建数组写入，构造确定、可复现。
fn osm_build_csr(n : Int, edges : Array[OsmEdge]) -> CsrGraph[Double] {
  let row_ptr : Array[Int] = []
  let col_idx : Array[Int] = []
  let weights : Array[Double] = []
  row_ptr.push(0)
  let mut cur_row = 0
  for e in edges {
    // 源跨行时，为 [cur_row+1 .. e.src] 的每一行写入当前累计偏移（空行）。
    while cur_row < e.src {
      row_ptr.push(col_idx.length())
      cur_row = cur_row + 1
    }
    col_idx.push(e.dst)
    weights.push(e.weight)
  }
  // 补齐剩余行（含末行）的偏移，使 row_ptr 长度达到 n + 1。
  while cur_row < n {
    row_ptr.push(col_idx.length())
    cur_row = cur_row + 1
  }
  CsrGraph::{ n, row_ptr, col_idx, weights }
}

///|
/// 以稳定三态比较器按 `(src, dst)` 升序就地排序边数组（避免整数相减溢出）。
fn osm_sort_edges(edges : Array[OsmEdge]) -> Unit {
  edges.sort_by(fn(a, b) {
    if a.src < b.src {
      -1
    } else if a.src > b.src {
      1
    } else if a.dst < b.dst {
      -1
    } else if a.dst > b.dst {
      1
    } else {
      0
    }
  })
}

///|
/// 解析 TSV 边表文本为 `CsrGraph[Double]`（生产级、不崩溃、结构化错误）。
///
/// 输入格式（与 `benches/osm/download.sh` 写出的 `xiamen.tsv` 对齐）：
///
/// - 每行三列、以制表符 `\t` 分隔：`src  dst  length_m`。
/// - 允许首行为表头（首字段非纯数字，如 `src`）：仅当其为**首个内容行**时跳过。
/// - 空行、仅含空白的行、以 `#` 起始的注释行一律跳过。
///
/// 行为保证：
///
/// - **结构化失败**（R8.7 / R22.6）：任何非首行的字段缺失（少于 3 列）、节点
///   标识非法（非纯非负整数）、边权非法（无法解析为有限非负数）均返回
///   `Err(InvalidArgument(...))`，诊断串携带出错行号与原因；不部分构造、不崩溃。
/// - **节点数推断**：`n = max(出现过的最大节点标识) + 1`；无任何边时返回有效空图
///   （`n = 0`）。调用方可据 `n == 0` 触发合成回退（见 `load_osm_or_synthetic`）。
/// - **确定性**：边按 `(src, dst)` 升序归并入 CSR，重复 `(src, dst)` 作为平行边
///   保留，构造结果可复现。
///
/// 诊断串经 `@infra_text.TextBuilder` 构建，无循环内字符串 `+` 拼接。
pub fn CsrGraph::from_osm_edge_list(
  content : String,
) -> Result[CsrGraph[Double], PathError] {
  let lines = osm_split_lines(content)
  let edges : Array[OsmEdge] = []
  let mut max_id = -1
  let mut seen_content = false
  let mut line_no = 0
  for raw in lines {
    line_no = line_no + 1
    let line = osm_trim(raw)
    // 跳过空行与注释行（不计入「首个内容行」判定）。
    if line.length() == 0 || osm_first_char(line) is Some('#') {
      continue
    }
    let fields = osm_split_fields(line)
    // 字段不足三列：表头候选（首个内容行）放行，否则结构化报错。
    if fields.length() < 3 {
      if !seen_content {
        seen_content = true
        continue
      }
      return Err(InvalidArgument(osm_line_error(line_no, "字段少于 3 列")))
    }
    let src_opt = osm_parse_node_id(fields[0])
    let dst_opt = osm_parse_node_id(fields[1])
    let w_opt = osm_parse_weight(fields[2])
    match (src_opt, dst_opt, w_opt) {
      (Some(src), Some(dst), Some(weight)) => {
        // 边权须为有限非负数（路网长度语义）：NaN / 负数视为非法。
        if weight.is_nan() || weight < 0.0 {
          return Err(
            InvalidArgument(
              osm_line_error(line_no, "边权须为有限非负数"),
            ),
          )
        }
        seen_content = true
        if src > max_id {
          max_id = src
        }
        if dst > max_id {
          max_id = dst
        }
        edges.push(OsmEdge::{ src, dst, weight })
      }
      _ =>
        // 首个内容行解析失败且首字段非数字 → 视为表头跳过一次；否则结构化报错。
        if !seen_content && osm_parse_node_id(fields[0]) is None {
          seen_content = true
          continue
        } else {
          return Err(
            InvalidArgument(
              osm_line_error(line_no, "节点标识或边权格式非法"),
            ),
          )
        }
    }
  }
  let n = max_id + 1
  osm_sort_edges(edges)
  Ok(osm_build_csr(n, edges))
}

///|
/// 构造「第 N 行 + 原因」的结构化解析诊断串（经 TextBuilder，无循环内 `+`）。
fn osm_line_error(line_no : Int, reason : String) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("OSM 边表解析失败：第 ")
  tb.push_str(line_no.to_string())
  tb.push_str(" 行 ")
  tb.push_str(reason)
  tb.build()
}

///|
/// 构造合成路网：`rows × cols` 的四邻接（上下左右）均匀代价网格，双向边。
///
/// 节点标识按行优先编号 `r * cols + c ∈ 0..rows*cols-1`；相邻格之间互置一条
/// 权重为 `weight` 的有向边（双向各一条）。用作 OSM 数据缺失时的安全回退图，
/// 其连通结构足以驱动 CH/ALT/Dijkstra 的正确性对拍（R8.7）。
///
/// 行为保证：
///
/// - **参数校验**：`rows <= 0` / `cols <= 0` / `weight` 为 NaN 或负数时返回
///   `Err(InvalidArgument(...))`，不部分构造。
/// - **确定性**：边按 `(src, dst)` 升序入 CSR，重复运行字节级一致。
pub fn synthetic_grid_csr(
  rows : Int,
  cols : Int,
  weight : Double,
) -> Result[CsrGraph[Double], PathError] {
  if rows <= 0 || cols <= 0 {
    return Err(
      InvalidArgument("synthetic_grid_csr: 行数与列数均须为正整数"),
    )
  }
  if weight.is_nan() || weight < 0.0 {
    return Err(
      InvalidArgument("synthetic_grid_csr: 边权须为有限非负数"),
    )
  }
  let n = rows * cols
  let edges : Array[OsmEdge] = []
  for r in 0..<rows {
    for c in 0..<cols {
      let node = r * cols + c
      // 右邻接（双向）。
      if c + 1 < cols {
        let right = node + 1
        edges.push(OsmEdge::{ src: node, dst: right, weight })
        edges.push(OsmEdge::{ src: right, dst: node, weight })
      }
      // 下邻接（双向）。
      if r + 1 < rows {
        let down = node + cols
        edges.push(OsmEdge::{ src: node, dst: down, weight })
        edges.push(OsmEdge::{ src: down, dst: node, weight })
      }
    }
  }
  osm_sort_edges(edges)
  Ok(osm_build_csr(n, edges))
}

///|
/// 加载 OSM 路网，数据缺失/为空/解析失败时安全降级为合成网格（R8.7）。
///
/// 决策（恒不报错、恒返回有效图）：
///
/// - `content == None` 或内容仅含空白 → 记录「数据缺失」诊断，改用合成网格。
/// - `content == Some(s)` 且解析成功且非空（`n > 0`）→ 采用真实 OSM 图，
///   `source = RealOsm`，诊断记录其节点/边规模。
/// - 解析成功但为空图（`n == 0`）→ 记录「数据为空」诊断，改用合成网格。
/// - 解析失败（`Err`）→ 记录解析失败原因诊断，改用合成网格。
///
/// `fallback_dim` 为合成网格的边长（行=列）；非正值时退化为 `osm_min_fallback_dim`，
/// 保证回退图至少含一个节点。合成图构造在参数已被守卫的前提下恒成功；为彻底
/// 杜绝任何潜在崩溃路径，构造失败时进一步退化为单节点空图（防御性兜底）。
pub fn load_osm_or_synthetic(
  content : String?,
  fallback_dim : Int,
) -> OsmLoadOutcome {
  match content {
    Some(s) =>
      if osm_trim(s).length() == 0 {
        osm_synthetic_outcome(
          fallback_dim, "OSM 数据为空（内容仅含空白）",
        )
      } else {
        match CsrGraph::from_osm_edge_list(s) {
          Ok(g) =>
            if g.n > 0 {
              osm_real_outcome(g)
            } else {
              osm_synthetic_outcome(
                fallback_dim, "OSM 数据为空（无有效边）",
              )
            }
          Err(e) => {
            // 将结构化解析错误的诊断并入降级诊断（单次顺序拼接，非循环）。
            let tb = @infra_text.TextBuilder::new()
            tb.push_str("OSM 数据解析失败，改用合成网格：")
            tb.push_str(e.message())
            osm_synthetic_outcome(fallback_dim, tb.build())
          }
        }
      }
    None =>
      osm_synthetic_outcome(
        fallback_dim, "OSM 数据缺失（未提供数据源）",
      )
  }
}

///|
/// 统计 CSR 图的有向边数（即 `col_idx` 的有效长度，与 `weights` 取较小者防御）。
fn osm_edge_count(g : CsrGraph[Double]) -> Int {
  if g.col_idx.length() < g.weights.length() {
    g.col_idx.length()
  } else {
    g.weights.length()
  }
}

///|
/// 由真实 OSM 图构造加载结果（来源 `RealOsm`，诊断记录其规模）。
fn osm_real_outcome(g : CsrGraph[Double]) -> OsmLoadOutcome {
  let ec = osm_edge_count(g)
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("已加载真实 OSM 路网子集：节点 ")
  tb.push_str(g.n.to_string())
  tb.push_str(" 个，有向边 ")
  tb.push_str(ec.to_string())
  tb.push_str(" 条")
  OsmLoadOutcome::{
    graph: g,
    source: RealOsm,
    node_count: g.n,
    edge_count: ec,
    diagnostic: tb.build(),
  }
}

///|
/// 构造合成网格降级结果（来源 `SyntheticFallback`，诊断拼接「缺失原因 + 合成规模」）。
fn osm_synthetic_outcome(fallback_dim : Int, reason : String) -> OsmLoadOutcome {
  let dim = if fallback_dim < osm_min_fallback_dim {
    osm_min_fallback_dim
  } else {
    fallback_dim
  }
  let g = match synthetic_grid_csr(dim, dim, 1.0) {
    Ok(grid) => grid
    // 防御性兜底：参数已被守卫，理论上不可达；仍以单节点空图避免任何崩溃。
    Err(_) => CsrGraph::{ n: 1, row_ptr: [0, 0], col_idx: [], weights: [] }
  }
  let ec = osm_edge_count(g)
  let tb = @infra_text.TextBuilder::new()
  tb.push_str(reason)
  tb.push_str("；已降级为合成网格：")
  tb.push_str(dim.to_string())
  tb.push_str("×")
  tb.push_str(dim.to_string())
  tb.push_str("（节点 ")
  tb.push_str(g.n.to_string())
  tb.push_str(" 个，有向边 ")
  tb.push_str(ec.to_string())
  tb.push_str(" 条）")
  OsmLoadOutcome::{
    graph: g,
    source: SyntheticFallback,
    node_count: g.n,
    edge_count: ec,
    diagnostic: tb.build(),
  }
}
