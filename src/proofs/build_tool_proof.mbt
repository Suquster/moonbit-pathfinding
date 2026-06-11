// build_tool_proof.mbt —— Build_Tool（R6，复用 @directed.topo_sort / condensation）
// 方向的证明谓词占位。
//
// 复用约定：增量「输入未变 → 零重建」空操作复用通用谓词 `is_idempotent`；
// 本文件补充方向特有的「调度顺序遵守依赖」最小占位谓词。谓词均为纯、全（total）。
// 升级路径：任务 9.x 引入真实 `BuildGraph` 后替换占位。

///|
/// 构建调度顺序遵守依赖（占位）。
///
/// `pos[i]` 给出节点 `i` 在调度序列中的位置；`edges` 中每条 `(u, v)` 表示
/// 「u 依赖 v」。当且仅当每条依赖的被依赖方 `v` 排在依赖方 `u` 之前
/// （`pos[v] < pos[u]`）时成立——即拓扑序不变量。下标越界视为非法，返回
/// `false` 以保持谓词总。
pub fn build_order_respects_deps(
  pos : Array[Int],
  edges : Array[(Int, Int)],
) -> Bool {
  let n = pos.length()
  let mut i = 0
  while i < edges.length() {
    let (u, v) = edges[i]
    if u < 0 || v < 0 || u >= n || v >= n {
      return false
    }
    if !(pos[v] < pos[u]) {
      return false
    }
    i += 1
  }
  true
}
