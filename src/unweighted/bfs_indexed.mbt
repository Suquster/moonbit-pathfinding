// bfs_indexed.mbt —— 稠密整数节点 BFS 快路径。
//
// 通用 `bfs` 以 `Map[N, _]` 承载 visited/parents，泛型 + 哈希在
// 「节点即 0..n-1 整数」的稠密图（本库基准/评测主负载）上是纯开销。
// 本变体以扁平 Array 承载全部状态 + CSR 邻接，语义与通用版逐位一致
// （同一图上返回路径边数相同），由差分 PBT 守卫。

///|
/// 稠密整数节点图的 CSR（compressed sparse row）邻接：
/// 节点 u 的后继为 `targets[offsets[u]..offsets[u+1])`。
pub struct CsrGraph {
  offsets : Array[Int]
  targets : Array[Int]
}

///|
/// 由边集 (u, v) 构建 CSR。O(V + E)。
pub fn CsrGraph::from_edges(n : Int, edges : Array[(Int, Int)]) -> CsrGraph {
  let counts = Array::make(n + 1, 0)
  for e in edges {
    let (u, _) = e
    counts[u + 1] = counts[u + 1] + 1
  }
  for i in 1..<=n {
    counts[i] = counts[i] + counts[i - 1]
  }
  let offsets = counts.copy()
  let cursor = Array::make(n, 0)
  for u in 0..<n {
    cursor[u] = offsets[u]
  }
  let targets = Array::make(edges.length(), 0)
  for e in edges {
    let (u, v) = e
    targets[cursor[u]] = v
    cursor[u] = cursor[u] + 1
  }
  { offsets, targets }
}

///|
/// 节点数。
pub fn CsrGraph::node_count(self : CsrGraph) -> Int {
  self.offsets.length() - 1
}

///|
/// 可复用 BFS 上下文：parent/代戳/队列数组只分配一次，跨查询用
/// generation 戳懒失效（免去每查询 O(n) 初始化——批量查询的主开销之一）。
pub struct BfsCtx {
  parent : Array[Int]
  stamp : Array[Int]
  queue : Array[Int]
  mut gen : Int
}

///|
/// 为节点数 n 的图创建可复用 BFS 上下文。
pub fn BfsCtx::new(n : Int) -> BfsCtx {
  {
    parent: Array::make(n, -2),
    stamp: Array::make(n, 0),
    queue: Array::make(n, 0),
    gen: 0,
  }
}

///|
/// 复用上下文的 BFS（语义与 `bfs_indexed` 一致；批量查询时免每次
/// O(n) 数组初始化）。上下文容量必须 ≥ 图节点数。
pub fn bfs_indexed_ctx(
  g : CsrGraph,
  ctx : BfsCtx,
  start : Int,
  target : Int,
) -> Array[Int]? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  if start == target {
    return Some([start])
  }
  ctx.gen = ctx.gen + 1
  let gen = ctx.gen
  let parent = ctx.parent
  let stamp = ctx.stamp
  let queue = ctx.queue
  parent[start] = -1
  stamp[start] = gen
  queue[0] = start
  let mut head = 0
  let mut tail = 1
  while head < tail {
    let cur = queue[head]
    head = head + 1
    let stop = g.offsets[cur + 1]
    for ei = g.offsets[cur]; ei < stop; ei = ei + 1 {
      let next = g.targets[ei]
      if stamp[next] == gen {
        continue
      }
      stamp[next] = gen
      parent[next] = cur
      if next == target {
        let path = [next]
        let mut node = next
        while parent[node] >= 0 {
          node = parent[node]
          path.push(node)
        }
        path.rev_in_place()
        return Some(path)
      }
      queue[tail] = next
      tail = tail + 1
    }
  }
  None
}

///|
/// 双向 BFS 可复用上下文：正/反两侧 parent/dist/代戳与队列各一份。
pub struct BiBfsCtx {
  parent_f : Array[Int]
  parent_b : Array[Int]
  dist_f : Array[Int]
  dist_b : Array[Int]
  stamp_f : Array[Int]
  stamp_b : Array[Int]
  queue_f : Array[Int]
  queue_b : Array[Int]
  mut gen : Int
}

///|
/// 为节点数 n 的图创建可复用双向 BFS 上下文。
pub fn BiBfsCtx::new(n : Int) -> BiBfsCtx {
  {
    parent_f: Array::make(n, -2),
    parent_b: Array::make(n, -2),
    dist_f: Array::make(n, 0),
    dist_b: Array::make(n, 0),
    stamp_f: Array::make(n, 0),
    stamp_b: Array::make(n, 0),
    queue_f: Array::make(n, 0),
    queue_b: Array::make(n, 0),
    gen: 0,
  }
}

///|
/// 双向 BFS（层同步）：正向沿 `g` 出边、反向沿 `rg`（g 的逆图）出边，
/// 每轮扩展前沿较小的一侧整层；两侧相遇后收该层最小会合点。返回
/// 与 `bfs_indexed` 边数相同的最短路径（路径本身可能不同但长度最优，
/// 差分 PBT 守卫）。随机图上搜索空间 ~O(b^(d/2))，远小于单向 O(b^d)。
pub fn bfs_bidirectional_ctx(
  g : CsrGraph,
  rg : CsrGraph,
  ctx : BiBfsCtx,
  start : Int,
  target : Int,
) -> Array[Int]? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  if start == target {
    return Some([start])
  }
  ctx.gen = ctx.gen + 1
  let gen = ctx.gen
  let pf = ctx.parent_f
  let pb = ctx.parent_b
  let df = ctx.dist_f
  let db = ctx.dist_b
  let sf = ctx.stamp_f
  let sb = ctx.stamp_b
  let qf = ctx.queue_f
  let qb = ctx.queue_b
  pf[start] = -1
  df[start] = 0
  sf[start] = gen
  qf[0] = start
  pb[target] = -1
  db[target] = 0
  sb[target] = gen
  qb[0] = target
  // [head, tail) 为当前层。
  let mut fh = 0
  let mut ft = 1
  let mut bh = 0
  let mut bt = 1
  let mut meet = -1
  let mut best = 0x3FFF_FFFF
  while fh < ft && bh < bt {
    if ft - fh <= bt - bh {
      // 扩展正向一层。
      let layer_end = ft
      while fh < layer_end {
        let cur = qf[fh]
        fh = fh + 1
        let stop = g.offsets[cur + 1]
        for ei = g.offsets[cur]; ei < stop; ei = ei + 1 {
          let next = g.targets[ei]
          if sf[next] == gen {
            continue
          }
          sf[next] = gen
          pf[next] = cur
          df[next] = df[cur] + 1
          if sb[next] == gen {
            let cand = df[next] + db[next]
            if cand < best {
              best = cand
              meet = next
            }
          }
          qf[ft] = next
          ft = ft + 1
        }
      }
    } else {
      // 扩展反向一层（rg 出边 = g 入边）。
      let layer_end = bt
      while bh < layer_end {
        let cur = qb[bh]
        bh = bh + 1
        let stop = rg.offsets[cur + 1]
        for ei = rg.offsets[cur]; ei < stop; ei = ei + 1 {
          let next = rg.targets[ei]
          if sb[next] == gen {
            continue
          }
          sb[next] = gen
          pb[next] = cur
          db[next] = db[cur] + 1
          if sf[next] == gen {
            let cand = df[next] + db[next]
            if cand < best {
              best = cand
              meet = next
            }
          }
          qb[bt] = next
          bt = bt + 1
        }
      }
    }
    if meet >= 0 {
      // 层同步下整层收尾后的最小会合即全局最优。
      let path = [meet]
      let mut node = meet
      while pf[node] >= 0 {
        node = pf[node]
        path.push(node)
      }
      path.rev_in_place()
      node = meet
      while pb[node] >= 0 {
        node = pb[node]
        path.push(node)
      }
      return Some(path)
    }
  }
  None
}

///|
/// 稠密整数节点 BFS：起点 `start` 到 `target` 的最短（边数）路径。
/// 状态全部为扁平数组（visited 位、parent 指针、环形队列），无哈希。
/// 返回 `Some(path)`（含两端）或 `None`。O(V + E)。
pub fn bfs_indexed(g : CsrGraph, start : Int, target : Int) -> Array[Int]? {
  let n = g.node_count()
  if start < 0 || start >= n || target < 0 || target >= n {
    return None
  }
  if start == target {
    return Some([start])
  }
  let parent = Array::make(n, -2) // -2 = 未访问，-1 = 起点根
  parent[start] = -1
  let queue = Array::make(n, 0)
  queue[0] = start
  let mut head = 0
  let mut tail = 1
  while head < tail {
    let cur = queue[head]
    head = head + 1
    let stop = g.offsets[cur + 1]
    for ei = g.offsets[cur]; ei < stop; ei = ei + 1 {
      let next = g.targets[ei]
      if parent[next] != -2 {
        continue
      }
      parent[next] = cur
      if next == target {
        let path = [next]
        let mut node = next
        while parent[node] >= 0 {
          node = parent[node]
          path.push(node)
        }
        path.rev_in_place()
        return Some(path)
      }
      queue[tail] = next
      tail = tail + 1
    }
  }
  None
}
