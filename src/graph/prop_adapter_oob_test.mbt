// Feature: championship-v1-upgrade, Property 25: Graph_Adapter 越界标识报错且底层不变
//
// 本文件以属性测试（property-based test）校验 `@graph.GraphRepr::neighbors`
// 在「越界节点标识」下的两条核心不变量（design.md §「Property 25」/
// Requirement 15.5）：
//
//   1. **越界即失败**：对任意逻辑图与任意越界节点标识（`< 0` 或 `>= N`），
//      `neighbors(node)` 返回 `Err(PathError)`，且具体为 `InvalidArgument`
//      变体（可由模式匹配判定）。
//   2. **底层不变**：越界查询不得修改底层图。由于 `GraphRepr` 为不可变值，
//      本属性以「越界调用前后，对全部合法节点的邻居查询结果逐一相等」来
//      佐证底层存储未被破坏——在多次越界调用之间穿插合法查询，结果须保持稳定。
//
// 逻辑图随机覆盖三种底层表示（AdjMatrix / EdgeList / CSR），由同一组随机
// 边集分别构造，使越界语义在三表上均被检验。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 256（远超 ≥100 基线）。

///|
/// 由「节点数 + 边三元组序列」构造邻接矩阵表示。
///
/// 初始化 `n x n` 的 `None` 矩阵，对每条边 `(s, t, w)` 置 `matrix[s][t] = Some(w)`。
/// 同一 `(s, t)` 多次出现时以最后一次写入为准（邻接矩阵单槽语义），不影响本属性
/// 对「越界报错 + 底层不变」的检验。
fn p25_build_adj(n : Int, edges : Array[(Int, Int, Int)]) -> GraphRepr[Int] {
  let matrix : Array[Array[Int?]] = []
  let mut i = 0
  while i < n {
    matrix.push(Array::make(n, None))
    i = i + 1
  }
  for e in edges {
    let (s, t, w) = e
    matrix[s][t] = Some(w)
  }
  AdjMatrix(n, matrix)
}

///|
/// 由「节点数 + 边三元组序列」构造 CSR（压缩稀疏行）表示。
///
/// 先统计各源节点出边数得到行偏移 `row_ptr`（前缀和），再以每源游标依序填充
/// `col_idx` / `weights`。所有源标识均落在 `0..n-1`（由生成器保证），故计数与
/// 写入下标恒合法。
fn p25_build_csr(n : Int, edges : Array[(Int, Int, Int)]) -> GraphRepr[Int] {
  let counts = Array::make(n, 0)
  for e in edges {
    let (s, _, _) = e
    counts[s] = counts[s] + 1
  }
  let row_ptr = Array::make(n + 1, 0)
  let mut acc = 0
  let mut i = 0
  while i < n {
    row_ptr[i] = acc
    acc = acc + counts[i]
    i = i + 1
  }
  row_ptr[n] = acc
  let total = acc
  let col_idx = Array::make(total, 0)
  let weights = Array::make(total, 0)
  let cursor = Array::make(n, 0)
  for e in edges {
    let (s, t, w) = e
    let pos = row_ptr[s] + cursor[s]
    col_idx[pos] = t
    weights[pos] = w
    cursor[s] = cursor[s] + 1
  }
  Csr({ n, row_ptr, col_idx, weights })
}

///|
/// 随机生成 `(逻辑图, 越界节点)`：节点数 1..8、边数 0..2n，随机择一种底层表示，
/// 并随机生成一个越界节点标识（负数 `-1..-5` 或 `>= n` 的 `n..n+4`）。
fn p25_gen() -> @infra_pbt.Gen[(GraphRepr[Int], Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 8) // 节点数 1..8（闭区间）
    let edge_count = rng.next_below(n * 2 + 1) // 边数 0..2n
    let edges : Array[(Int, Int, Int)] = []
    let mut k = 0
    while k < edge_count {
      let s = rng.next_below(n) // 源 0..n-1
      let t = rng.next_below(n) // 目标 0..n-1
      let w = rng.next_range(1, 100) // 边权 1..100
      edges.push((s, t, w))
      k = k + 1
    }
    // 随机选择三种底层表示之一，使越界语义在三表上均被覆盖。
    let repr = match rng.next_below(3) {
      0 => p25_build_adj(n, edges)
      1 => EdgeList(n, edges)
      _ => p25_build_csr(n, edges)
    }
    // 随机越界节点：负数 或 >= n。
    let oob = if rng.next_bool() {
      -(1 + rng.next_below(5)) // 负数：-1..-5
    } else {
      n + rng.next_below(5) // 越上界：n..n+4
    }
    (repr, oob)
  })
}

///|
/// 拍快照：依次查询全部合法节点 `0..n-1` 的邻居结果，用于越界调用前后比对。
fn p25_legal_snapshot(
  repr : GraphRepr[Int],
  n : Int,
) -> Array[Result[Array[(Int, Int)], PathError]] {
  let snap : Array[Result[Array[(Int, Int)], PathError]] = []
  let mut i = 0
  while i < n {
    snap.push(repr.neighbors(i))
    i = i + 1
  }
  snap
}

///|
/// Feature: championship-v1-upgrade, Property 25: Graph_Adapter 越界标识报错且底层不变
///
/// 对任意逻辑图与越界节点标识：
///   * `neighbors(oob)` 返回 `Err(InvalidArgument(_))`；且
///   * 在多次越界调用前后，对全部合法节点的邻居查询结果逐一相等（佐证底层
///     图未被越界调用修改）。
///
/// **Validates: Requirements 15.5**
test "Feature: championship-v1-upgrade, Property 25: graph adapter out-of-bounds errors and leaves graph intact" {
  let ok = @infra_pbt.holds_for_all(
    p25_gen(),
    fn(input) {
      let (repr, oob) = input
      let n = repr.node_count()
      // 越界调用前：合法节点邻居快照。
      let before = p25_legal_snapshot(repr, n)
      // 不变量 1：随机越界标识必须返回 Err(InvalidArgument(_))。
      match repr.neighbors(oob) {
        Err(InvalidArgument(_)) => ()
        _ => return false
      }
      // 进一步以两个恒越界标识（-1 与 n）多次查询，强化「底层不变」检验。
      match repr.neighbors(-1) {
        Err(InvalidArgument(_)) => ()
        _ => return false
      }
      match repr.neighbors(n) {
        Err(InvalidArgument(_)) => ()
        _ => return false
      }
      // 不变量 2：越界调用后，合法节点邻居快照应与调用前完全一致。
      let after = p25_legal_snapshot(repr, n)
      if before.length() != after.length() {
        return false
      }
      let mut i = 0
      while i < before.length() {
        if before[i] != after[i] {
          return false
        }
        i = i + 1
      }
      true
    },
    iters=256,
  )
  assert_true(ok)
}
