// 黑盒测试：覆盖率审计收口（INFRA 第七十八批）——
// 畸形邻接矩阵/CSR 的防御裁剪、后继闭包投影与含换行空白内容的
// OSM 空数据识别。

///|
test "GraphRepr::neighbors：畸形短行矩阵按行长裁剪" {
  let ragged : Array[Array[Int?]] = [
    [None, Some(3)],
    [Some(1)],
    [None, None, None],
  ]
  let g : @graph.GraphRepr[Int] = @graph.GraphRepr::AdjMatrix(3, ragged)
  guard g.neighbors(1) is Ok(ns)
  assert_eq(ns, [(0, 1)])
}

///|
test "GraphRepr::neighbors：畸形 CSR 边数按较短数组裁剪" {
  let csr : @graph.CsrGraph[Int] = @graph.CsrGraph::{
    n: 2,
    row_ptr: [0, 2, 2],
    col_idx: [1],
    weights: [5, 7],
  }
  let g : @graph.GraphRepr[Int] = @graph.GraphRepr::Csr(csr)
  guard g.neighbors(0) is Ok(ns)
  assert_eq(ns, [(1, 5)])
}

///|
test "GraphRepr::to_successors：闭包投影越界返回空" {
  let g : @graph.GraphRepr[Int] = @graph.GraphRepr::EdgeList(2, [(0, 1, 4)])
  let succ = g.to_successors()
  assert_eq(succ(0), [(1, 4)])
  assert_eq(succ(9), [])
}

///|
test "load_osm_or_synthetic：仅含换行的内容识别为空数据" {
  let out = @graph.load_osm_or_synthetic(Some(" \n \n"), 4)
  assert_true(out.diagnostic.contains("内容仅含空白"))
  assert_true(out.node_count > 0)
}
