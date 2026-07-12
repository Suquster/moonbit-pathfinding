// OSM 图模式导出层（osm.mbt）—— 真实路网点到点路由的整型句柄协议。
//
// 与网格模式（exports.mbt）平行的第二会话：宿主 JS 先以
// `pg_osm_reset(n)` 声明节点数，`pg_osm_add_edge(src, dst, w)` 逐条注入
// 有向边（权为非负整型，单位由宿主约定，如分米），`pg_osm_build()` 物化
// CSR（正向 + 反向邻接），随后 `pg_osm_route(algo, s, t)` 在 MoonBit 侧
// 运行单向 Dijkstra（algo=0）或双向 Dijkstra（algo=1），再按下标以
// `pg_osm_path_len / pg_osm_path_at / pg_osm_cost / pg_osm_settled` 拉取
// 扁平整型结果。协议延续 exports.mbt 的「句柄 + 扁平整型读取」设计与
// 零异常路径（整型错误码，见 `err_*` 常量）。
//
// 体积约束：与网格模式同包自洽实现（仅 @core.PQueue），不链接算法包，
// 维持 wasm-gc 产物 ≤102400 字节门禁（scripts/wasm_size_guard.ps1）。

///|
/// OSM 图模式算法码：单向 Dijkstra。
let osm_algo_dijkstra : Int = 0

///|
/// OSM 图模式算法码：双向 Dijkstra。
let osm_algo_bidirectional : Int = 1

///|
/// OSM 图模式的单一全局会话。
///
/// - `node_count`：`pg_osm_reset` 声明的节点数；0 表示未初始化。
/// - `edge_src/edge_dst/edge_w`：`pg_osm_add_edge` 暂存的边表。
/// - `built`：`pg_osm_build` 是否已物化 CSR。
/// - `fwd_head/fwd_next/fwd_dst/fwd_w`：正向邻接（头插链式 CSR）。
/// - `rev_*`：反向邻接（双向搜索用）。
/// - `path`：最近一次成功路由的节点序列（含起终点）。
/// - `cost`：最近一次成功路由的总权；不可达为 -1。
/// - `settled`：最近一次路由确定（settle）的节点数（工作量证据）。
/// - `last_error`：最近一次操作的错误码。
priv struct OsmSession {
  mut node_count : Int
  edge_src : Array[Int]
  edge_dst : Array[Int]
  edge_w : Array[Int]
  mut built : Bool
  mut fwd_head : Array[Int]
  mut fwd_next : Array[Int]
  mut fwd_dst : Array[Int]
  mut fwd_w : Array[Int]
  mut rev_head : Array[Int]
  mut rev_next : Array[Int]
  mut rev_dst : Array[Int]
  mut rev_w : Array[Int]
  mut path : Array[Int]
  mut cost : Int
  mut settled : Int
  mut last_error : Int
}

///|
/// OSM 图模式进程级会话句柄（单元素数组承载可变实例）。
let osm_session : Array[OsmSession] = [
  {
    node_count: 0,
    edge_src: [],
    edge_dst: [],
    edge_w: [],
    built: false,
    fwd_head: [],
    fwd_next: [],
    fwd_dst: [],
    fwd_w: [],
    rev_head: [],
    rev_next: [],
    rev_dst: [],
    rev_w: [],
    path: [],
    cost: sentinel_none,
    settled: 0,
    last_error: err_ok,
  },
]

///|
/// 重置 OSM 图会话为 `n` 个节点的空图。
///
/// `n <= 0` 返回 `err_invalid_argument`；成功返回 `err_ok` 并清空边表、
/// CSR 与上次路由结果。
pub fn pg_osm_reset(n : Int) -> Int {
  let s = osm_session[0]
  if n <= 0 {
    s.last_error = err_invalid_argument
    return err_invalid_argument
  }
  s.node_count = n
  s.edge_src.clear()
  s.edge_dst.clear()
  s.edge_w.clear()
  s.built = false
  s.path = []
  s.cost = sentinel_none
  s.settled = 0
  s.last_error = err_ok
  err_ok
}

///|
/// 注入一条有向边 `src -> dst`，非负整型权 `w`。
///
/// 未 reset、端点越界或 `w < 0` 返回 `err_invalid_argument`；build 之后
/// 再添边同样拒绝（需重新 reset）。
pub fn pg_osm_add_edge(src : Int, dst : Int, w : Int) -> Int {
  let s = osm_session[0]
  if s.node_count <= 0 ||
    s.built ||
    src < 0 ||
    src >= s.node_count ||
    dst < 0 ||
    dst >= s.node_count ||
    w < 0 {
    s.last_error = err_invalid_argument
    return err_invalid_argument
  }
  s.edge_src.push(src)
  s.edge_dst.push(dst)
  s.edge_w.push(w)
  s.last_error = err_ok
  err_ok
}

///|
/// 物化正向与反向邻接（头插链式 CSR）。未 reset 或已 build 返回
/// `err_invalid_argument`。
pub fn pg_osm_build() -> Int {
  let s = osm_session[0]
  if s.node_count <= 0 || s.built {
    s.last_error = err_invalid_argument
    return err_invalid_argument
  }
  let n = s.node_count
  let m = s.edge_src.length()
  s.fwd_head = Array::make(n, sentinel_none)
  s.fwd_next = Array::make(m, sentinel_none)
  s.fwd_dst = Array::make(m, 0)
  s.fwd_w = Array::make(m, 0)
  s.rev_head = Array::make(n, sentinel_none)
  s.rev_next = Array::make(m, sentinel_none)
  s.rev_dst = Array::make(m, 0)
  s.rev_w = Array::make(m, 0)
  for i in 0..<m {
    let u = s.edge_src[i]
    let v = s.edge_dst[i]
    let w = s.edge_w[i]
    s.fwd_dst[i] = v
    s.fwd_w[i] = w
    s.fwd_next[i] = s.fwd_head[u]
    s.fwd_head[u] = i
    s.rev_dst[i] = u
    s.rev_w[i] = w
    s.rev_next[i] = s.rev_head[v]
    s.rev_head[v] = i
  }
  s.built = true
  s.last_error = err_ok
  err_ok
}

///|
/// 单向 Dijkstra：返回 `(dist, parent, settled_count)`；`t` settle 后提前
/// 终止。`dist[v] = sentinel_none` 表示未达。
fn osm_dijkstra_uni(
  s : OsmSession,
  src : Int,
  t : Int,
) -> (Array[Int], Array[Int], Int) {
  let n = s.node_count
  let dist : Array[Int] = Array::make(n, sentinel_none)
  let parent : Array[Int] = Array::make(n, sentinel_none)
  let done : Array[Bool] = Array::make(n, false)
  let pq : @core.PQueue[Int, Int] = @core.PQueue::new()
  dist[src] = 0
  pq.push(0, src)
  let mut settled = 0
  while pq.pop() is Some((d, u)) {
    if done[u] {
      continue
    }
    done[u] = true
    settled = settled + 1
    if u == t {
      break
    }
    let mut e = s.fwd_head[u]
    while e != sentinel_none {
      let v = s.fwd_dst[e]
      let nd = d + s.fwd_w[e]
      if dist[v] == sentinel_none || nd < dist[v] {
        dist[v] = nd
        parent[v] = u
        pq.push(nd, v)
      }
      e = s.fwd_next[e]
    }
  }
  (dist, parent, settled)
}

///|
/// 双向 Dijkstra：正向自 `src`、反向自 `t` 交替扩展，以
/// `top_f + top_b >= best` 终止，返回 `(best_cost, meet, parent_f,
/// parent_b, settled_count)`；不可达时 `best_cost = sentinel_none`。
fn osm_dijkstra_bidir(
  s : OsmSession,
  src : Int,
  t : Int,
) -> (Int, Int, Array[Int], Array[Int], Int) {
  let n = s.node_count
  let dist_f : Array[Int] = Array::make(n, sentinel_none)
  let dist_b : Array[Int] = Array::make(n, sentinel_none)
  let parent_f : Array[Int] = Array::make(n, sentinel_none)
  let parent_b : Array[Int] = Array::make(n, sentinel_none)
  let done_f : Array[Bool] = Array::make(n, false)
  let done_b : Array[Bool] = Array::make(n, false)
  let pq_f : @core.PQueue[Int, Int] = @core.PQueue::new()
  let pq_b : @core.PQueue[Int, Int] = @core.PQueue::new()
  dist_f[src] = 0
  dist_b[t] = 0
  pq_f.push(0, src)
  pq_b.push(0, t)
  let mut best = sentinel_none
  let mut meet = sentinel_none
  let mut settled = 0
  while !pq_f.is_empty() && !pq_b.is_empty() {
    match (pq_f.peek(), pq_b.peek()) {
      (Some((df, _)), Some((db, _))) =>
        if best != sentinel_none && df + db >= best {
          break
        }
      _ => break
    }
    // 交替扩展较小堆顶的一侧
    let forward = match (pq_f.peek(), pq_b.peek()) {
      (Some((df, _)), Some((db, _))) => df <= db
      _ => true
    }
    if forward {
      match pq_f.pop() {
        Some((d, u)) => {
          if done_f[u] {
            continue
          }
          done_f[u] = true
          settled = settled + 1
          let mut e = s.fwd_head[u]
          while e != sentinel_none {
            let v = s.fwd_dst[e]
            let nd = d + s.fwd_w[e]
            if dist_f[v] == sentinel_none || nd < dist_f[v] {
              dist_f[v] = nd
              parent_f[v] = u
              pq_f.push(nd, v)
            }
            if dist_b[v] != sentinel_none {
              let cand = nd + dist_b[v]
              if best == sentinel_none || cand < best {
                best = cand
                meet = v
              }
            }
            e = s.fwd_next[e]
          }
          if dist_b[u] != sentinel_none {
            let cand = d + dist_b[u]
            if best == sentinel_none || cand < best {
              best = cand
              meet = u
            }
          }
        }
        None => break
      }
    } else {
      match pq_b.pop() {
        Some((d, u)) => {
          if done_b[u] {
            continue
          }
          done_b[u] = true
          settled = settled + 1
          let mut e = s.rev_head[u]
          while e != sentinel_none {
            let v = s.rev_dst[e]
            let nd = d + s.rev_w[e]
            if dist_b[v] == sentinel_none || nd < dist_b[v] {
              dist_b[v] = nd
              parent_b[v] = u
              pq_b.push(nd, v)
            }
            if dist_f[v] != sentinel_none {
              let cand = nd + dist_f[v]
              if best == sentinel_none || cand < best {
                best = cand
                meet = v
              }
            }
            e = s.rev_next[e]
          }
          if dist_f[u] != sentinel_none {
            let cand = d + dist_f[u]
            if best == sentinel_none || cand < best {
              best = cand
              meet = u
            }
          }
        }
        None => break
      }
    }
  }
  (best, meet, parent_f, parent_b, settled)
}

///|
/// 在已 build 的图上路由：`algo` 为 0（单向 Dijkstra）或 1（双向
/// Dijkstra）。成功（含「合法不可达」）返回 `err_ok`；未 build、端点
/// 越界或算法码非法返回 `err_invalid_argument`。不可达时
/// `pg_osm_path_len()` 为 -1（与网格模式 R3.4 语义一致）。
pub fn pg_osm_route(algo : Int, src : Int, t : Int) -> Int {
  let s = osm_session[0]
  if !s.built ||
    src < 0 ||
    src >= s.node_count ||
    t < 0 ||
    t >= s.node_count ||
    (algo != osm_algo_dijkstra && algo != osm_algo_bidirectional) {
    s.last_error = err_invalid_argument
    return err_invalid_argument
  }
  s.path = []
  s.cost = sentinel_none
  s.settled = 0
  if algo == osm_algo_dijkstra {
    let (dist, parent, settled) = osm_dijkstra_uni(s, src, t)
    s.settled = settled
    if dist[t] != sentinel_none {
      s.cost = dist[t]
      let rev : Array[Int] = []
      let mut cur = t
      while cur != sentinel_none {
        rev.push(cur)
        cur = parent[cur]
      }
      let path : Array[Int] = []
      let mut i = rev.length() - 1
      while i >= 0 {
        path.push(rev[i])
        i = i - 1
      }
      s.path = path
    }
  } else {
    let (best, meet, parent_f, parent_b, settled) = osm_dijkstra_bidir(
      s, src, t,
    )
    s.settled = settled
    if best != sentinel_none {
      s.cost = best
      let rev : Array[Int] = []
      let mut cur = meet
      while cur != sentinel_none {
        rev.push(cur)
        cur = parent_f[cur]
      }
      let path : Array[Int] = []
      let mut i = rev.length() - 1
      while i >= 0 {
        path.push(rev[i])
        i = i - 1
      }
      let mut cur2 = parent_b[meet]
      while cur2 != sentinel_none {
        path.push(cur2)
        cur2 = parent_b[cur2]
      }
      s.path = path
    }
  }
  s.last_error = err_ok
  err_ok
}

///|
/// 最近一次路由的路径长度（节点数）。不可达为 -1；从未成功路由过也为 -1。
pub fn pg_osm_path_len() -> Int {
  let s = osm_session[0]
  if s.cost == sentinel_none {
    sentinel_none
  } else {
    s.path.length()
  }
}

///|
/// 按下标读取最近一次路由路径中的节点 id；越界返回 -1。
pub fn pg_osm_path_at(i : Int) -> Int {
  let s = osm_session[0]
  if i < 0 || i >= s.path.length() {
    sentinel_none
  } else {
    s.path[i]
  }
}

///|
/// 最近一次路由的总权；不可达为 -1。
pub fn pg_osm_cost() -> Int {
  osm_session[0].cost
}

///|
/// 最近一次路由确定（settle）的节点数——单向 vs 双向工作量对比的证据值。
pub fn pg_osm_settled() -> Int {
  osm_session[0].settled
}

///|
/// OSM 图会话最近一次操作的错误码（`err_ok` = 0 表示成功）。
pub fn pg_osm_last_error() -> Int {
  osm_session[0].last_error
}
