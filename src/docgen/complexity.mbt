// complexity.mbt —— 算法复杂度元数据模型与 Markdown 复杂度表生成（方向 6 · R19）。
//
// 设计依据（design.md §6.1「Doc_Generator 与 Complexity_Table」/ Requirement 19）：
//   * 以精确结构体 `AlgoMeta` 表示「算法名 + 最坏时间 + 平均时间 + 空间 +
//     适用条件」五个字段，禁止用字符串模拟结构化数据（R22.6）。
//   * `algorithm_metadata()` 返回库内静态常量数组，恰好 33 条：30 种经典图/
//     路径算法（与 README 算法目录 1–30 一一对应）+ Contraction Hierarchies /
//     Jump Point Search / ALT（R19.1/R19.2）。
//   * `complexity_table()` 以 `@infra_text.TextBuilder` 顺序追加片段，生成耗时
//     随算法数量 O(n) 线性增长，构建文本时不在循环内做字符串 `+` 拼接（R19.4）。
//   * 任一元数据的任一必填字段为空 → 先于任何文本构建返回
//     `Err(@graph.PathError::InvalidArgument(...))`，绝不产生部分写入（R19.5）。

///|
/// 复杂度表应覆盖的算法总数：30 种经典算法 + CH / JPS / ALT（R19.2）。
///
/// 以命名常量替代散落的字面量 `33`，便于断言与未来维护时单点修改。
/// `algorithm_metadata()` 返回的元数据条目数必须恰好等于该常量，
/// `complexity_table` 生成的数据行数亦与之一致（见 Property 29 完整性校验）。
/// 新增算法时同步更新本常量与元数据表，二者偏离即触发属性测试失败。
pub let algorithm_count : Int = 33

///|
/// Markdown 表格的单元格分隔符（竖线两侧留空格，符合 GFM 渲染习惯）。
let cell_separator : String = " | "

///|
/// Markdown 表格行的行首竖线（含前导空格）。
let row_prefix : String = "| "

///|
/// Markdown 表格行的行尾竖线（含换行，逐行追加，避免循环内字符串拼接）。
let row_suffix : String = " |\n"

///|
/// 算法元数据模型（精确结构体，禁止字符串模拟结构 · R22.6）。
///
/// 五个字段均为「必填」：生成复杂度表时任一字段为空都会导致失败（R19.5）。
///
/// - `name`：算法名称（唯一标识，复杂度表内不重复、不遗漏 · R19.2）。
/// - `worst_time`：最坏情况时间复杂度。
/// - `avg_time`：平均情况时间复杂度。
/// - `space`：额外空间复杂度。
/// - `applicability`：典型适用条件 / 场景。
///
/// 可见性为 `pub(all)`：除库内 `algorithm_metadata()` 外，属性测试（Property
/// 30/31）需在黑盒测试中按随机字段构造 `AlgoMeta` 实例以驱动 `complexity_table`，
/// 故开放字段构造能力（纯数据模型，无内部不变量约束）。
pub(all) struct AlgoMeta {
  name : String
  worst_time : String
  avg_time : String
  space : String
  applicability : String
} derive(Eq, Debug)

///|
/// 判断一段元数据文本是否为「空必填字段」（长度为 0 即视为缺失 · R19.5）。
fn is_blank_field(field : String) -> Bool {
  field.length() == 0
}

///|
/// 校验单条元数据的全部必填字段；若存在空字段，返回对应字段名用于诊断。
///
/// 返回 `None` 表示该条元数据合法；返回 `Some(字段名)` 表示首个为空的字段。
fn first_blank_field(meta : AlgoMeta) -> String? {
  if is_blank_field(meta.name) {
    Some("name")
  } else if is_blank_field(meta.worst_time) {
    Some("worst_time")
  } else if is_blank_field(meta.avg_time) {
    Some("avg_time")
  } else if is_blank_field(meta.space) {
    Some("space")
  } else if is_blank_field(meta.applicability) {
    Some("applicability")
  } else {
    None
  }
}

///|
/// 向文本构建器追加一行 Markdown 表格内容（五列），全程顺序 `push_str`，
/// 不做任何字符串 `+` 拼接（R19.4）。
fn push_table_row(
  tb : @infra_text.TextBuilder,
  c1 : String,
  c2 : String,
  c3 : String,
  c4 : String,
  c5 : String,
) -> Unit {
  tb.push_str(row_prefix)
  tb.push_str(c1)
  tb.push_str(cell_separator)
  tb.push_str(c2)
  tb.push_str(cell_separator)
  tb.push_str(c3)
  tb.push_str(cell_separator)
  tb.push_str(c4)
  tb.push_str(cell_separator)
  tb.push_str(c5)
  tb.push_str(row_suffix)
}

///|
/// 从算法元数据生成 Markdown 复杂度表（R19.1/R19.3/R19.4/R19.5）。
///
/// 表格形如：
/// ```text
/// | 算法 | 最坏时间复杂度 | 平均时间复杂度 | 空间复杂度 | 适用条件 |
/// | --- | --- | --- | --- | --- |
/// | BFS | O(V + E) | O(V + E) | O(V) | 无权图最短路 / 可达性 |
/// ...
/// ```
///
/// 行为约定：
/// - **逐元数据一行**：输出行数与输入条数一致，每行内容由对应元数据完全决定
///   （R19.3）。
/// - **O(n) 线性 + 无循环内拼接**：遍历一次元数据数组，统一经 `TextBuilder`
///   顺序追加片段；表格物化为单次 `build()`，不在循环内使用字符串 `+`（R19.4）。
/// - **空字段即失败、绝不部分写入**：先完整校验所有元数据（先于任何文本构建），
///   一旦发现某条的某个必填字段为空，立即返回
///   `Err(@graph.PathError::InvalidArgument(...))`；此时尚未向构建器写入任何
///   表格内容，故不产生部分写入（R19.5）。
pub fn complexity_table(
  metas : Array[AlgoMeta],
) -> Result[String, @graph.PathError] {
  // 阶段一：先做全量校验。任何文本构建都发生在校验通过之后，从根本上
  // 杜绝「部分写入」——失败时调用方持有的上一份有效表不被触碰（R19.5）。
  for i = 0; i < metas.length(); i = i + 1 {
    match first_blank_field(metas[i]) {
      Some(field) => {
        let diag = @infra_text.TextBuilder::new()
        diag.push_str("complexity_table: 第 ")
        diag.push_str(i.to_string())
        diag.push_str(" 条算法元数据的必填字段 '")
        diag.push_str(field)
        diag.push_str("' 为空")
        return Err(@graph.PathError::InvalidArgument(diag.build()))
      }
      None => ()
    }
  }
  // 阶段二：校验已全部通过，开始 O(n) 线性构建表格文本。
  let tb = @infra_text.TextBuilder::new()
  // 表头与对齐分隔行（固定两行，非循环，单次顺序追加）。
  push_table_row(
    tb, "算法", "最坏时间复杂度", "平均时间复杂度", "空间复杂度",
    "适用条件",
  )
  push_table_row(tb, "---", "---", "---", "---", "---")
  // 数据行：每条元数据恰好一行，全程经 TextBuilder 追加，无循环内 `+`。
  for i = 0; i < metas.length(); i = i + 1 {
    let m = metas[i]
    push_table_row(
      tb,
      m.name,
      m.worst_time,
      m.avg_time,
      m.space,
      m.applicability,
    )
  }
  Ok(tb.build())
}

///|
/// 库内静态算法复杂度元数据（恰好 `algorithm_count` 条 · R19.1/R19.2）。
///
/// 前 30 条与 README「算法目录」编号 1–30 一一对应，末 3 条为旗舰高级算法
/// Contraction Hierarchies / Jump Point Search / ALT。每条的五个字段均非空。
/// 复杂度记号中 V 表示节点数、E 表示边数、b 表示分支因子、d 表示解深度、
/// K 表示请求的路径条数、F 表示最大流值、L 表示地标数量。
pub fn algorithm_metadata() -> Array[AlgoMeta] {
  [
    {
      name: "BFS",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V)",
      applicability: "无权图最短路 / 可达性遍历",
    },
    {
      name: "DFS",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V)",
      applicability: "遍历 / 连通性 / 拓扑与回溯基础",
    },
    {
      name: "Dijkstra",
      worst_time: "O((V + E) log V)",
      avg_time: "O((V + E) log V)",
      space: "O(V)",
      applicability: "非负权单源最短路",
    },
    {
      name: "A*",
      worst_time: "O((V + E) log V)",
      avg_time: "依启发式可远优于 Dijkstra",
      space: "O(V)",
      applicability: "带可采纳启发式的单源最短路",
    },
    {
      name: "Bellman-Ford",
      worst_time: "O(V · E)",
      avg_time: "O(V · E)",
      space: "O(V)",
      applicability: "含负权边的单源最短路 / 负环检测",
    },
    {
      name: "Floyd-Warshall",
      worst_time: "O(V^3)",
      avg_time: "O(V^3)",
      space: "O(V^2)",
      applicability: "稠密图全对最短路",
    },
    {
      name: "Kruskal MST",
      worst_time: "O(E log E)",
      avg_time: "O(E log E)",
      space: "O(V + E)",
      applicability: "稀疏图最小生成树",
    },
    {
      name: "Connected Components",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V)",
      applicability: "无向图连通分量划分",
    },
    {
      name: "Bidirectional BFS",
      worst_time: "O(V + E)",
      avg_time: "O(b^(d/2))",
      space: "O(V)",
      applicability: "无权图大跨度双向搜索",
    },
    {
      name: "Topological Sort",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V)",
      applicability: "DAG 线性化排序",
    },
    {
      name: "Tarjan SCC",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V)",
      applicability: "有向图强连通分量",
    },
    {
      name: "Edmonds-Karp",
      worst_time: "O(V · E^2)",
      avg_time: "O(V · E^2)",
      space: "O(V + E)",
      applicability: "一般容量网络最大流",
    },
    {
      name: "IDA*",
      worst_time: "O(b^d)",
      avg_time: "依启发式而定",
      space: "O(d)",
      applicability: "内存受限的启发式搜索",
    },
    {
      name: "Yen K-Shortest Paths",
      worst_time: "O(K · V · (E + V log V))",
      avg_time: "O(K · V · (E + V log V))",
      space: "O(K · V + E)",
      applicability: "无环 K 条最短路枚举",
    },
    {
      name: "Kuhn-Munkres",
      worst_time: "O(V^3)",
      avg_time: "O(V^3)",
      space: "O(V^2)",
      applicability: "二分图最大权完美匹配",
    },
    {
      name: "Prim MST",
      worst_time: "O(E log V)",
      avg_time: "O(E log V)",
      space: "O(V)",
      applicability: "稠密图最小生成树",
    },
    {
      name: "DAG Shortest Path",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V)",
      applicability: "DAG 最短路（可含负权）",
    },
    {
      name: "Bridges & Articulation Points",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V)",
      applicability: "无向图桥与割点检测",
    },
    {
      name: "Bidirectional Dijkstra",
      worst_time: "O((V + E) log V)",
      avg_time: "通常优于单向 Dijkstra",
      space: "O(V)",
      applicability: "非负权点对点最短路",
    },
    {
      name: "Dijkstra (full SSSP tree)",
      worst_time: "O((V + E) log V)",
      avg_time: "O((V + E) log V)",
      space: "O(V)",
      applicability: "非负权单源最短路树",
    },
    {
      name: "BFS (full SSSP tree)",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V)",
      applicability: "无权单源最短路树",
    },
    {
      name: "Bellman-Ford (path tree)",
      worst_time: "O(V · E)",
      avg_time: "O(V · E)",
      space: "O(V)",
      applicability: "含负权单源最短路树",
    },
    {
      name: "Floyd-Warshall + paths",
      worst_time: "O(V^3)",
      avg_time: "O(V^3)",
      space: "O(V^2)",
      applicability: "全对最短路 + 路径重建",
    },
    {
      name: "Johnson",
      worst_time: "O(V · E + V^2 log V)",
      avg_time: "O(V · E + V^2 log V)",
      space: "O(V^2)",
      applicability: "稀疏图全对最短路（可含负权）",
    },
    {
      name: "Dinic",
      worst_time: "O(V^2 · E)",
      avg_time: "单位容量网络可达 O(E · sqrt(V))",
      space: "O(V + E)",
      applicability: "网络最大流（稠密 / 单位容量更优）",
    },
    {
      name: "Min s-t Cut",
      worst_time: "O(V · E^2)",
      avg_time: "O(V · E^2)",
      space: "O(V + E)",
      applicability: "最大流导出的最小 s-t 割",
    },
    {
      name: "Min-Cost Max-Flow",
      worst_time: "O(V · E · F)",
      avg_time: "O(V · E · F)",
      space: "O(V + E)",
      applicability: "带费用网络的最小费用最大流",
    },
    {
      name: "Hopcroft-Karp",
      worst_time: "O(E · sqrt(V))",
      avg_time: "O(E · sqrt(V))",
      space: "O(V + E)",
      applicability: "二分图最大基数匹配",
    },
    {
      name: "Eulerian Path (Hierholzer)",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V + E)",
      applicability: "欧拉路径 / 欧拉回路",
    },
    {
      name: "SCC Condensation DAG",
      worst_time: "O(V + E)",
      avg_time: "O(V + E)",
      space: "O(V + E)",
      applicability: "强连通分量缩点为 DAG",
    },
    {
      name: "Contraction Hierarchies",
      worst_time: "O(E log V)（预处理）",
      avg_time: "查询近 O(log V)",
      space: "O(V + E + 捷径数)",
      applicability: "静态道路网超快点对点查询",
    },
    {
      name: "Jump Point Search",
      worst_time: "O(V + E)",
      avg_time: "通常远优于 A*",
      space: "O(V)",
      applicability: "均匀代价网格无障碍跳点加速",
    },
    {
      name: "ALT",
      worst_time: "O((V + E) log V)",
      avg_time: "借助地标下界优于 A*",
      space: "O(V + L · V)",
      applicability: "带地标三角下界的道路网最短路",
    },
  ]
}
