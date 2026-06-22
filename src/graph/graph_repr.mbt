// graph_repr.mbt —— 通用图适配器 `GraphRepr[W]` 与 `CsrGraph[W]`（统一邻居接口）。
//
// 设计依据（design.md §「方向 4 · 4.4 Graph_Adapter（邻接矩阵 / 边表 / CSR）」/
// Requirement 15）：
//   将三种常见底层图存储——邻接矩阵（Adjacency_Matrix）、边表（Edge_List）、
//   压缩稀疏行（CSR）——统一暴露为「查询某节点全部出边邻居」的接口，使开发者
//   无需手动改写数据结构即可复用既有算法（R15.1）。本类型以**新增适配器类型**
//   形式提供，不修改任何既有算法的公开签名（R15.6）。
//
// 关键不变量（统一由 `neighbors` 保证，三表共享同一后处理）：
//   * R15.2：同一逻辑图的三种表示经 `neighbors` 查询产出相等的邻居集合与边权。
//     因三表均统一做「升序输出」后处理，不区分底层内部排列，故结果天然一致。
//   * R15.3：返回该节点在底层格式中记录的全部出边邻居，不遗漏、不重复，并以
//     目标节点标识升序排列；对同一节点的重复调用返回顺序一致（排序结果确定，
//     且全程只读底层图、构造全新结果数组，故可重复且稳定）。
//   * R15.4：查询无出边的孤立节点返回空邻居的成功结果 `Ok([])`。
//   * R15.5：越界节点标识（`< 0` 或 `>= N`）返回携带 `PathError` 的失败结果
//     `Err(InvalidArgument(...))`，并保持底层图不被修改（本实现全程只读，且仅向
//     新建的局部数组写入，绝不改动 `self` 持有的底层存储）。
//
// 质量约束（项目 steering）：
//   * 全程 `///|` 块注释、中文说明；无 `abort`/`todo!`/`panic` 占位。
//   * 无 O(n²) 字符串拼接（本文件不做文本累加；诊断串仅单次构造）。
//   * 以精确枚举/结构体表示结构化数据，不用字符串模拟（R22.6）。
//   * 复用同包既有 `PathError`（path_error.mbt），不新增错误类型、不改公开签名。

///|
/// 压缩稀疏行（CSR，Compressed Sparse Row）图表示。
///
/// 以「行偏移 + 列索引 + 边权」三数组紧凑表示稀疏有向图，节点标识为 `0..n-1`：
///
/// - `n`：节点数量，有效节点标识范围为 `0` 至 `n-1`。
/// - `row_ptr`：长度应为 `n + 1` 的行偏移数组；节点 `v` 的出边占据
///   `col_idx`/`weights` 的区间 `[row_ptr[v], row_ptr[v+1])`。
/// - `col_idx`：列索引数组，第 `k` 项为第 `k` 条出边的目标节点标识。
/// - `weights`：与 `col_idx` 一一对齐的边权数组，第 `k` 项为第 `k` 条出边的权重。
///
/// 字段以 `pub(all)` 暴露，便于调用方/测试直接以三数组构造 CSR 图。
pub(all) struct CsrGraph[W] {
  n : Int
  row_ptr : Array[Int]
  col_idx : Array[Int]
  weights : Array[W]
}

///|
/// 三种底层存储格式的统一表示。节点标识统一为 `0..N-1` 的 `Int`。
///
/// - `AdjMatrix(n, matrix)`：`n x n` 邻接矩阵；`matrix[i][j]` 为 `None` 表示
///   `i -> j` 无边，`Some(w)` 表示存在权重为 `w` 的边。
/// - `EdgeList(n, edges)`：节点数 `n` 加上 `(源, 目标, 权重)` 三元组序列；
///   同一源节点的出边可在序列中以任意次序出现。
/// - `Csr(graph)`：压缩稀疏行表示（见 `CsrGraph`）。
pub(all) enum GraphRepr[W] {
  AdjMatrix(Int, Array[Array[W?]])
  EdgeList(Int, Array[(Int, Int, W)])
  Csr(CsrGraph[W])
}

///|
/// 返回该表示的节点数量 `N`（有效节点标识范围为 `0..N-1`）。
///
/// 三种变体的节点数分别取自其携带的 `n` 字段，保持只读、不触碰底层存储。
pub fn[W] GraphRepr::node_count(self : GraphRepr[W]) -> Int {
  match self {
    AdjMatrix(n, _) => n
    EdgeList(n, _) => n
    Csr(g) => g.n
  }
}

///|
/// 按目标节点标识升序就地排序邻居数组（稳定比较，仅作用于新建的局部数组）。
///
/// 比较器以显式三态返回值避免整数相减潜在溢出，确保三后端确定一致（R15.3）。
fn[W] sort_neighbors_by_target(items : Array[(Int, W)]) -> Unit {
  items.sort_by(fn(a, b) {
    let (ta, _) = a
    let (tb, _) = b
    if ta < tb {
      -1
    } else if ta > tb {
      1
    } else {
      0
    }
  })
}

///|
/// 查询指定节点的全部出边邻居 `(目标节点, 边权)`。
///
/// 行为保证：
///
/// - **越界即失败且不改图**（R15.5）：当 `node < 0` 或 `node >= N` 时，返回
///   `Err(InvalidArgument(...))`，附带可读诊断；底层图全程只读，不被修改。
/// - **孤立节点空成功**（R15.4）：节点合法但无任何出边时返回 `Ok([])`。
/// - **不遗漏不重复 + 升序 + 可重复**（R15.3）：返回底层格式中记录的全部出边，
///   按目标节点标识升序排列；本方法仅读取底层存储并向新建数组写入，故对同一
///   节点的重复调用返回顺序一致。
/// - **三表一致**（R15.2）：三种变体均经统一的升序后处理输出，故同一逻辑图的
///   不同表示产出相等的邻居集合与边权（不区分底层内部排列）。
pub fn[W] GraphRepr::neighbors(
  self : GraphRepr[W],
  node : Int,
) -> Result[Array[(Int, W)], PathError] {
  let n = self.node_count()
  // 越界检查（R15.5）：先于任何读取做边界判定，失败路径不接触底层存储。
  if node < 0 || node >= n {
    let tb = @infra_text.TextBuilder::new()
    tb.push_str("neighbors: 节点标识 ")
    tb.push_str(node.to_string())
    tb.push_str(" 越界，合法范围为 0..")
    tb.push_str((n - 1).to_string())
    tb.push_str("（共 ")
    tb.push_str(n.to_string())
    tb.push_str(" 个节点）")
    return Err(InvalidArgument(tb.build()))
  }
  let out : Array[(Int, W)] = []
  match self {
    AdjMatrix(_, matrix) => {
      // 读取第 node 行；仅遍历 [0, min(n, 行长)) 内的列，规避畸形（非 n x n）矩阵越界。
      let row = matrix[node]
      let cols = if row.length() < n { row.length() } else { n }
      for j in 0..<cols {
        match row[j] {
          Some(w) => out.push((j, w))
          None => ()
        }
      }
    }
    EdgeList(_, edges) =>
      // 扫描三元组序列，收集源等于 node 的出边；目标越界（不在 0..N-1）者跳过，
      // 以保证仅产出合法邻居（与邻接矩阵/CSR 的语义口径一致）。
      for e in edges {
        let (s, t, w) = e
        if s == node && t >= 0 && t < n {
          out.push((t, w))
        }
      }
    Csr(g) =>
      // 取第 node 行的边区间 [row_ptr[node], row_ptr[node+1])；对畸形 CSR 做防御性
      // 边界裁剪，避免 row_ptr / col_idx / weights 长度不一致时越界访问。
      if node + 1 < g.row_ptr.length() {
        let start = g.row_ptr[node]
        let stop = g.row_ptr[node + 1]
        let edge_count = if g.col_idx.length() < g.weights.length() {
          g.col_idx.length()
        } else {
          g.weights.length()
        }
        let lo = if start < 0 { 0 } else { start }
        let hi = if stop > edge_count { edge_count } else { stop }
        for k in lo..<hi {
          let t = g.col_idx[k]
          if t >= 0 && t < n {
            out.push((t, g.weights[k]))
          }
        }
      }
  }
  // 统一升序后处理：保证三表一致、升序、对重复调用顺序稳定（R15.2 / R15.3）。
  sort_neighbors_by_target(out)
  Ok(out)
}

///|
/// 适配为既有算法所需的 successor 闭包：给定节点产出其出边邻居 `(目标, 边权)` 数组。
///
/// 闭包内部复用 `neighbors`：合法节点返回其升序邻居数组；越界节点产出空数组
/// （越界判定与「不改底层图」保证均由 `neighbors` 承担）。该形式让任意底层表示
/// 无缝接入以 `(Int) -> Array[(Int, W)]` 为 successor 抽象的算法（R15.1 / R15.6）。
pub fn[W] GraphRepr::to_successors(
  self : GraphRepr[W],
) -> (Int) -> Array[(Int, W)] {
  fn(node) {
    match self.neighbors(node) {
      Ok(ns) => ns
      Err(_) => []
    }
  }
}
