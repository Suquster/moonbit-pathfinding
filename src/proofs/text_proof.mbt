// text_proof.mbt —— INFRA 家族第九批证明谓词：文本引擎（infra_text：
// Myers diff / PieceTable / Rope / Unicode 折叠与簇切分）的不变量接入。
//
// 复用约定：与其余 `*_proof.mbt` 相同——每条不变量编码为纯、全（total）的
// `Bool` 谓词，proofs 生产代码不引入新依赖（仅 @core / @infra_text），
// 跨包驱动只发生在测试期（text_proof_test.mbt 以真实包实现接地）。
//
// 覆盖的不变量家族：
//   * 差分最优性（Myers 编辑代价 == |a| + |b| − 2·LCS，与 DP 参考闭式一致）；
//   * 双向还原（diff_source 还原 a、diff_apply 还原 b）；
//   * 切分重组（grapheme 簇拼接还原原串——切分无损）；
//   * 模型等价（PieceTable / Rope 随机编辑脚本与朴素 String 模型逐步一致，
//     测试期直接驱动）。

///|
/// `diff_optimal_cost(cost, len_a, len_b, lcs)` —— 差分最优性闭式：最优
/// 编辑脚本（仅插入/删除）的代价恰为 `len_a + len_b - 2*lcs`。任何声称
/// 最优的 diff 引擎（Myers 等）产出的 `diff_edit_cost` 必须与该闭式一致
/// ——多一步即非最优，少一步即无法完成变换。纯、全函数。
pub fn diff_optimal_cost(
  cost : Int,
  len_a : Int,
  len_b : Int,
  lcs : Int,
) -> Bool {
  cost == len_a + len_b - 2 * lcs
}

///|
/// `partition_reassembles(parts, whole)` —— 切分无损谓词：分片顺序拼接
/// 恰好还原整体。用于 grapheme 簇切分（`grapheme_clusters` 拼接 == 原串）、
/// 行切分等一切「切分-重组」往返。纯、全函数（空整体要求空分片集）。
pub fn partition_reassembles(parts : Array[String], whole : String) -> Bool {
  let mut acc = ""
  let mut i = 0
  while i < parts.length() {
    acc = acc + parts[i]
    i += 1
  }
  acc == whole
}

///|
/// `equivalence_laws(x, y, z, eq)` —— 等价关系三律合取：自反
/// （`eq(x, x)`）、对称（`eq(x, y) == eq(y, x)`）、传递（`eq(x, y)` 且
/// `eq(y, z)` 蕴含 `eq(x, z)`）。用于大小写折叠等价 `eq_fold` 等自定义
/// 相等判定的合法性。纯、全函数，供随机字符串三元组 PBT 驱动。
pub fn equivalence_laws(
  x : String,
  y : String,
  z : String,
  eq : (String, String) -> Bool,
) -> Bool {
  eq(x, x) && eq(x, y) == eq(y, x) && (!(eq(x, y) && eq(y, z)) || eq(x, z))
}
