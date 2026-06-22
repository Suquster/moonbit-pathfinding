// Feature: championship-v1-upgrade, Property 24: Graph_Adapter 三表邻居一致、升序、确定
//
// 本文件以属性测试（property-based test）校验通用图适配器 `GraphRepr[W]` 的
// 三种底层存储表示——邻接矩阵（AdjMatrix）、边表（EdgeList）、压缩稀疏行
// （Csr）——在统一邻居查询接口 `neighbors` 下的等价性与确定性
// （design.md §「Property 24」/ Requirement 15.2、15.3）：
//
//   1. **三表一致**（R15.2）：对同一逻辑图与任意节点，三种表示经 `neighbors`
//      查询产出**完全相等**的邻居数组（相同的 (目标节点, 边权) 序列）。
//   2. **升序、不遗漏不重复**（R15.3）：返回数组按目标节点标识严格升序排列；
//      因构造时采用「同一 (u,v) 唯一边」的简单图，故目标节点互不重复。
//   3. **重复调用顺序一致**（R15.3）：对同一表示、同一节点重复调用两次，返回
//      数组逐元素相等（结果确定、可复现）。
//
// 为保证三表严格等价，生成阶段以邻接矩阵为「唯一真相来源」（matrix[u][v] 至多
// 一条边），再由该简单图派生 EdgeList 与 CSR，从根本上规避平行边导致的不一致。
// 为强化「升序后处理」的检验强度，派生的边表会被随机洗牌（打乱插入顺序）。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 128（≥100 基线）。

///|
/// 单个随机逻辑图的三表打包：节点数 `n` 与同一简单图的三种 `GraphRepr[Int]` 表示。
///
/// 三个字段均派生自同一邻接矩阵真相来源，故在 `neighbors` 下应严格等价。
struct P24Graph {
  n : Int
  adj : GraphRepr[Int]
  edges : GraphRepr[Int]
  csr : GraphRepr[Int]
}

///|
/// 以 `rng` 对数组就地做 Fisher–Yates 洗牌，用于打乱派生边表的插入顺序。
///
/// 洗牌后边表内出边的出现次序与矩阵扫描序无关，从而真正考验 `neighbors` 的
/// 「升序后处理」是否稳定（而非偶然沿用了底层排列）。
fn p24_shuffle(rng : @infra_pbt.Rng, items : Array[(Int, Int, Int)]) -> Unit {
  let len = items.length()
  let mut i = len - 1
  while i > 0 {
    let j = rng.next_below(i + 1) // [0, i] 内取交换下标
    let tmp = items[i]
    items[i] = items[j]
    items[j] = tmp
    i = i - 1
  }
}

///|
/// 随机逻辑图生成器：先以邻接矩阵为唯一真相来源生成简单图，再派生三种表示。
///
/// 生成规则：
///   * 节点数 `n ∈ [1, 7]`；
///   * 以「随机投放」方式置边：对若干 (u, v) 写入随机权重，重复写入同一 (u, v)
///     仅覆盖权重，保证「同一 (u,v) 唯一边」（简单图，无平行边）；允许自环。
///   * 由矩阵派生：
///       - EdgeList：扫描矩阵收集 (u, v, w)，随后随机洗牌；
///       - CSR：按行分组（行内目标天然升序），构造 row_ptr / col_idx / weights。
fn p24_gen() -> @infra_pbt.Gen[P24Graph] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 7) // 节点数 1..7
    // 1) 邻接矩阵：唯一真相来源，初始全 None。
    let matrix : Array[Array[Int?]] = []
    for _u in 0..<n {
      let row : Array[Int?] = []
      for _v in 0..<n {
        row.push(None)
      }
      matrix.push(row)
    }
    // 2) 随机投放边：尝试次数 0..(n*n)，重复 (u,v) 覆盖权重 → 保证唯一边。
    let attempts = rng.next_below(n * n + 1)
    let mut k = 0
    while k < attempts {
      let u = rng.next_below(n)
      let v = rng.next_below(n)
      let w = rng.next_range(1, 100) // 边权 1..100
      matrix[u][v] = Some(w)
      k = k + 1
    }
    // 3) 派生 EdgeList：扫描矩阵收集三元组，再随机洗牌打乱次序。
    let edge_arr : Array[(Int, Int, Int)] = []
    for u in 0..<n {
      for v in 0..<n {
        match matrix[u][v] {
          Some(w) => edge_arr.push((u, v, w))
          None => ()
        }
      }
    }
    p24_shuffle(rng, edge_arr)
    // 4) 派生 CSR：按行分组（行内自然升序），构造 row_ptr/col_idx/weights。
    let row_ptr : Array[Int] = []
    let col_idx : Array[Int] = []
    let weights : Array[Int] = []
    row_ptr.push(0)
    for u in 0..<n {
      for v in 0..<n {
        match matrix[u][v] {
          Some(w) => {
            col_idx.push(v)
            weights.push(w)
          }
          None => ()
        }
      }
      row_ptr.push(col_idx.length())
    }
    let csr = CsrGraph::{ n, row_ptr, col_idx, weights }
    P24Graph::{
      n,
      adj: AdjMatrix(n, matrix),
      edges: EdgeList(n, edge_arr),
      csr: Csr(csr),
    }
  })
}

///|
/// 解包成功的邻居结果；失败时返回哨兵 `[(-1, -1)]` 以使后续相等比较必然暴露问题。
///
/// 在本属性中所有查询节点均合法（0..n-1），正常路径恒为 `Ok`；哨兵仅用于把
/// 「意外的 Err」转化为可被相等断言捕获的差异，而非静默吞掉。
fn p24_unwrap(r : Result[Array[(Int, Int)], PathError]) -> Array[(Int, Int)] {
  match r {
    Ok(ns) => ns
    Err(_) => [(-1, -1)]
  }
}

///|
/// 判断邻居数组是否按「目标节点标识」严格升序（简单图无重复目标，故应严格递增）。
fn p24_strictly_ascending(items : Array[(Int, Int)]) -> Bool {
  let mut i = 1
  while i < items.length() {
    let (prev, _) = items[i - 1]
    let (cur, _) = items[i]
    if prev >= cur {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 24: Graph_Adapter 三表邻居一致、升序、确定
///
/// 对任意随机逻辑图与其全部节点 `v ∈ 0..n-1`：
///   * 三种表示的 `neighbors(v)` 返回**逐元素相等**的数组（三表一致 · R15.2）；
///   * 该数组按目标节点严格升序、无重复目标（升序、不遗漏不重复 · R15.3）；
///   * 对同一表示重复调用两次返回相等数组（顺序确定可复现 · R15.3）。
///
/// **Validates: Requirements 15.2, 15.3**
test "Feature: championship-v1-upgrade, Property 24: graph adapter three-representation neighbor consistency" {
  let ok = @infra_pbt.holds_for_all(
    p24_gen(),
    fn(g) {
      let mut v = 0
      while v < g.n {
        let na = p24_unwrap(g.adj.neighbors(v))
        let ne = p24_unwrap(g.edges.neighbors(v))
        let nc = p24_unwrap(g.csr.neighbors(v))
        // 三表一致（R15.2）：邻接矩阵 == 边表 == CSR。
        if na != ne || na != nc {
          return false
        }
        // 升序且无重复目标（R15.3）。
        if !p24_strictly_ascending(na) {
          return false
        }
        // 重复调用顺序一致（R15.3）：再查一次三表，均与首次相等。
        let na2 = p24_unwrap(g.adj.neighbors(v))
        let ne2 = p24_unwrap(g.edges.neighbors(v))
        let nc2 = p24_unwrap(g.csr.neighbors(v))
        if na2 != na || ne2 != ne || nc2 != nc {
          return false
        }
        v = v + 1
      }
      true
    },
    iters=128,
  )
  assert_true(ok)
}
