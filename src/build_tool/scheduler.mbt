// scheduler.mbt —— 并行调度增强：关键路径与最小批次层数（旗舰深化，旁路新增）。
//
// paper-to-code（design.md §4.5 / §「算法说明」）：DAG **最长路径**（关键路径）
// 经**拓扑序动态规划**求解（Kahn 拓扑序上 `longest[v] = 1 + max(longest[u])`，
// O(V+E)）。对无环图，关键路径长度（节点数）恰等于不限并行度（`jobs <= 0`）下
// `schedule` 产出的批次层数——每层剥离入度为 0 节点对应一层关键路径推进，
// 故 `critical_path_length(g) == len(schedule(g, 0))`（正确性属性 12）。
//
// 既有 `schedule` 冻结复用（R13）：本文件**不改** `schedule`，仅新增关键路径
// 分析。`schedule` 的拓扑 / 批内独立 / 确定性 / jobs 约束四项不变量由属性测试
// （属性 8–11）固化。

///|
/// 关键路径长度：构建图最长依赖链的节点数。
///
/// 等于不限并行度（`jobs <= 0`）下完成构建所需的最小批次层数（R7.4）。环图
/// 无定义的关键路径，返回 0。
pub fn critical_path_length(g : BuildGraph) -> Int {
  match topo_order(g) {
    Err(_) => 0
    Ok(order) => {
      let longest : Map[Target, Int] = Map([])
      for n in g.nodes {
        longest[n] = 1
      }
      // 拓扑序保证前驱先于后继处理：对每条边 (u, v) 用 longest[u]+1 松弛 v。
      for u in order {
        let lu = longest.get(u).unwrap_or(1)
        for edge in g.edges {
          let (a, b) = edge
          if a == u {
            let lb = longest.get(b).unwrap_or(1)
            if lu + 1 > lb {
              longest[b] = lu + 1
            }
          }
        }
      }
      let mut maxv = 0
      for n in g.nodes {
        let l = longest.get(n).unwrap_or(1)
        if l > maxv {
          maxv = l
        }
      }
      maxv
    }
  }
}

///|
/// 不限并行度下完成构建所需的最小批次层数（= `critical_path_length`；对无环图
/// 等于 `len(schedule(g, 0))`，R7.4）。
pub fn min_layers(g : BuildGraph) -> Int {
  critical_path_length(g)
}
