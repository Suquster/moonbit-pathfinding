// dominator.mbt —— 支配树与支配边界，旗舰深化旁路新增。
//
// paper-to-code：
//   * 支配树：Lengauer-Tarjan 1979《A Fast Algorithm for Finding Dominators
//     in a Flowgraph》——DFS 编号 → 半支配者（semidominator）→ 经带路径压缩的
//     forest（EVAL/LINK）求直接支配者（idom）。
//   * 支配边界：Cytron et al. 1991《Efficiently Computing Static Single
//     Assignment Form and the Control Dependence Graph》的 DF 计算。
//
// 设计落点（design.md §4.2，R5）：不可达块不参与 DFS，从而被排除出支配树
// （R5.4）；除入口外每个可达节点恰有一个 idom（R5.2）；输出确定性（可达集与
// idom 映射顺序由 DFS 编号与块序决定，不依赖 Map 遍历顺序，R16.1）。

// ---------------------------------------------------------------------------
// 支配树
// ---------------------------------------------------------------------------

///|
/// 支配树（Dominator Tree）。
///
/// `root` 为唯一入口；`idom` 为「可达非入口节点 → 直接支配者」（入口不在键集）；
/// `children` 为 idom 的反向（支配树父 → 子，按 DFS 序）；`reachable` 为自入口
/// 可达的块（按 DFS 编号顺序，确定性）。
pub(all) struct DomTree {
  root : String
  idom : Map[String, String]
  children : Map[String, Array[String]]
  reachable : Array[String]
} derive(Debug)

///|
/// Lengauer-Tarjan EVAL 的路径压缩子过程。
fn lt_compress(
  v : Int,
  ancestor : Array[Int],
  label : Array[Int],
  semi : Array[Int],
) -> Unit {
  if ancestor[ancestor[v]] != -1 {
    lt_compress(ancestor[v], ancestor, label, semi)
    if semi[label[ancestor[v]]] < semi[label[v]] {
      label[v] = label[ancestor[v]]
    }
    ancestor[v] = ancestor[ancestor[v]]
  }
}

///|
/// Lengauer-Tarjan EVAL：返回从 `v` 起 forest 路径上半支配者编号最小的标记。
fn lt_eval(
  v : Int,
  ancestor : Array[Int],
  label : Array[Int],
  semi : Array[Int],
) -> Int {
  if ancestor[v] == -1 {
    return label[v]
  }
  lt_compress(v, ancestor, label, semi)
  label[v]
}

///|
/// 以 Lengauer-Tarjan 算法构造支配树。
///
/// 先自 `entry` 做 DFS 编号（不可达块不被访问，从而排除出支配树）；再按 DFS
/// 逆序求半支配者并经 EVAL/LINK 求 idom；最后一遍校正 idom。返回的 `idom` 映射
/// 不含入口键。
pub fn build_dom_tree(blocks : Array[BasicBlock], entry~ : String) -> DomTree {
  let succ : Map[String, Array[String]] = Map([])
  for b in blocks {
    succ[b.label] = b.succs
  }
  // ---- DFS 编号 ----
  let dfnum : Map[String, Int] = Map([])
  let vertex : Array[String] = []
  let parent_lbl : Array[String] = []
  let visited : Map[String, Bool] = Map([])
  // 仅当 entry 存在于块集合中才展开（否则返回空树）。
  if succ.contains(entry) {
    let stack : Array[(String, String)] = [(entry, "")]
    while stack.length() > 0 {
      let (v, par) = stack.pop().unwrap()
      if visited.contains(v) {
        continue
      }
      visited[v] = true
      dfnum[v] = vertex.length()
      vertex.push(v)
      parent_lbl.push(par)
      let ss = succ.get(v).unwrap_or([])
      let mut i = ss.length() - 1
      while i >= 0 {
        if succ.contains(ss[i]) && !visited.contains(ss[i]) {
          stack.push((ss[i], v))
        }
        i = i - 1
      }
    }
  }
  let n = vertex.length()
  // ---- 初始化 LT 数据结构 ----
  let semi : Array[Int] = Array::make(n, 0)
  let idom_num : Array[Int] = Array::make(n, -1)
  let ancestor : Array[Int] = Array::make(n, -1)
  let label : Array[Int] = Array::make(n, 0)
  let parent_num : Array[Int] = Array::make(n, -1)
  let bucket : Array[Array[Int]] = []
  let preds_num : Array[Array[Int]] = []
  for i in 0..<n {
    semi[i] = i
    label[i] = i
    bucket.push([])
    preds_num.push([])
    let pl = parent_lbl[i]
    parent_num[i] = if pl == "" { -1 } else { dfnum.get(pl).unwrap_or(-1) }
  }
  // 前驱（仅可达块之间）。
  for u in vertex {
    for s in succ.get(u).unwrap_or([]) {
      match dfnum.get(s) {
        Some(sn) => preds_num[sn].push(dfnum.get(u).unwrap())
        None => ()
      }
    }
  }
  // ---- 主循环：自高编号向低编号（跳过根 0）----
  let mut w = n - 1
  while w >= 1 {
    for v in preds_num[w] {
      let u = lt_eval(v, ancestor, label, semi)
      if semi[u] < semi[w] {
        semi[w] = semi[u]
      }
    }
    bucket[semi[w]].push(w)
    ancestor[w] = parent_num[w]
    let pw = parent_num[w]
    if pw >= 0 {
      for v in bucket[pw] {
        let u = lt_eval(v, ancestor, label, semi)
        idom_num[v] = if semi[u] < semi[v] { u } else { pw }
      }
      bucket[pw] = []
    }
    w = w - 1
  }
  // ---- 校正 ----
  let mut i = 1
  while i < n {
    if idom_num[i] != semi[i] {
      idom_num[i] = idom_num[idom_num[i]]
    }
    i = i + 1
  }
  // ---- 组装结果 ----
  let idom : Map[String, String] = Map([])
  let children : Map[String, Array[String]] = Map([])
  for lbl in vertex {
    children[lbl] = []
  }
  let mut k = 1
  while k < n {
    let par = vertex[idom_num[k]]
    idom[vertex[k]] = par
    children.get(par).unwrap().push(vertex[k])
    k = k + 1
  }
  let reachable : Array[String] = []
  for lbl in vertex {
    reachable.push(lbl)
  }
  let root = if n > 0 { vertex[0] } else { entry }
  { root, idom, children, reachable }
}

///|
/// 判定 `a` 是否支配 `b`（含 `a == b`）：自 `b` 沿 idom 父链上溯能到达 `a`。
pub fn DomTree::dominates(self : DomTree, a : String, b : String) -> Bool {
  let mut x = b
  let limit = self.reachable.length() + 1
  let mut steps = 0
  while steps <= limit {
    if x == a {
      return true
    }
    match self.idom.get(x) {
      Some(p) => x = p
      None => return x == a
    }
    steps = steps + 1
  }
  false
}

// ---------------------------------------------------------------------------
// 支配边界（Cytron DF）
// ---------------------------------------------------------------------------

///|
/// 计算每个块的支配边界集合。
///
/// Cytron et al. DF 算法：对每个前驱数 ≥ 2 的汇合块 `n`，对其每个前驱 `p`，自
/// `p` 沿 idom 链上溯至 `idom(n)`（不含），途中每个节点的 DF 加入 `n`。返回的
/// 每个 DF 列表按字典序排序，保证三后端确定性。
pub fn dominance_frontier(
  blocks : Array[BasicBlock],
  dom : DomTree,
) -> Map[String, Array[String]] {
  let reach : Map[String, Bool] = Map([])
  for r in dom.reachable {
    reach[r] = true
  }
  // 可达块之间的前驱（按块序）。
  let preds : Map[String, Array[String]] = Map([])
  for r in dom.reachable {
    preds[r] = []
  }
  for b in blocks {
    if !reach.contains(b.label) {
      continue
    }
    for s in b.succs {
      if reach.contains(s) {
        preds.get(s).unwrap().push(b.label)
      }
    }
  }
  let df : Map[String, Array[String]] = Map([])
  for r in dom.reachable {
    df[r] = []
  }
  for b in dom.reachable {
    let ps = preds.get(b).unwrap_or([])
    if ps.length() < 2 {
      continue
    }
    let stop = match dom.idom.get(b) {
      Some(s) => s
      None => continue // b 为根（无 idom），不会有 ≥2 前驱触发 DF
    }
    for p in ps {
      let mut runner = p
      let limit = dom.reachable.length() + 1
      let mut steps = 0
      while runner != stop && steps <= limit {
        let lst = df.get(runner).unwrap_or([])
        if !array_contains_str(lst, b) {
          lst.push(b)
          df[runner] = lst
        }
        match dom.idom.get(runner) {
          Some(nx) => runner = nx
          None => break
        }
        steps = steps + 1
      }
    }
  }
  for r in dom.reachable {
    let lst = df.get(r).unwrap_or([])
    lst.sort()
    df[r] = lst
  }
  df
}
