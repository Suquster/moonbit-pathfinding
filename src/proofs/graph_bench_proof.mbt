// graph_bench_proof.mbt —— INFRA 家族第七批证明谓词：图容器（graph：
// CSR/构建器端点封闭与计数守恒）、基准统计（infra_bench：统计量排序律 +
// 报告 JSON 往返）、模糊收缩（infra_fuzz：收缩良基性）与文档生成
// （docgen：复杂度表完备性）的不变量接入。
//
// 复用约定：与其余 `*_proof.mbt` 相同——每条不变量编码为纯、全（total）的
// `Bool` 谓词，proofs 生产代码不引入新依赖（仅 @core），跨包驱动只发生在
// 测试期（graph_bench_proof_test.mbt 以真实包实现接地）。
//
// 覆盖的不变量家族：
//   * 端点封闭（图中每条边两端点均落在 [0, n) 节点域内）；
//   * 统计量排序律（min ≤ median ≤ p95 ≤ max、mean ∈ [min, max]，
//     复用 non_decreasing_f）；
//   * 往返恒等（BenchReport to_json ∘ from_json，复用 round_trip_eq）；
//   * 收缩良基（每个收缩候选的规模严格小于原件——保证反例最小化终止）；
//   * 文本完备（复杂度表包含全部算法名，复用 contains_all）。

///|
/// `endpoints_in_range(edges, n)` —— 端点封闭谓词：边表中每条边 `(u, v)`
/// 的两端点均落在节点域 `[0, n)` 内。用于 CSR/构建器产出图的结构良构性
/// ——任何算法在其上的邻接访问不会越界。纯、全函数（空边表平凡为真）。
pub fn endpoints_in_range(edges : Array[(Int, Int)], n : Int) -> Bool {
  let mut i = 0
  while i < edges.length() {
    let (u, v) = edges[i]
    if u < 0 || u >= n || v < 0 || v >= n {
      return false
    }
    i += 1
  }
  true
}

///|
/// `all_strictly_less(sizes, bound)` —— 收缩良基性谓词：每个收缩候选的
/// 规模严格小于原件规模 `bound`。严格递减保证反例最小化在有限步内终止
/// （良基归纳）。纯、全函数（空候选集平凡为真——无可收缩即终止）。
pub fn all_strictly_less(sizes : Array[Int], bound : Int) -> Bool {
  let mut i = 0
  while i < sizes.length() {
    if sizes[i] >= bound {
      return false
    }
    i += 1
  }
  true
}
