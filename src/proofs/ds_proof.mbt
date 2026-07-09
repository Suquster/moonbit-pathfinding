// ds_proof.mbt —— INFRA 家族第五批证明谓词：数据结构（infra_ds：
// BTreeMap / SkipList / HamtMap / RoaringBitmap / LruCache / BloomFilter）
// 的不变量接入。
//
// 复用约定：与其余 `*_proof.mbt` 相同——每条不变量编码为纯、全（total）的
// `Bool` 谓词，proofs 生产代码不引入新依赖（仅 @core），跨包驱动只发生在
// 测试期（ds_proof_test.mbt 以真实包实现接地）。
//
// 覆盖的不变量家族：
//   * 有序遍历（BTreeMap/SkipList `to_array` 键严格递增）；
//   * 区间封闭（`range(lo, hi)` 结果键均落在 [lo, hi]）；
//   * 集合代数（Roaring 并/交结果与逐元素成员判定一致，
//     经 subset_of 双向包含表述）；
//   * 容量硬上界（LruCache size ≤ cap，复用 all_within）；
//   * 无假阴性（BloomFilter 已插入元素必命中，经 forall 谓词表述）。

///|
/// `sorted_strict(xs)` —— 有序遍历谓词：序列严格递增（`xs[i] < xs[i+1]`）。
/// 用于有序容器（BTreeMap / SkipList）`to_array` 输出的键序不变量——严格
/// 递增同时蕴含键互异（无重复键）。纯、全函数（长度 < 2 平凡为真）。
pub fn sorted_strict(xs : Array[Int]) -> Bool {
  let mut i = 0
  while i + 1 < xs.length() {
    if xs[i] >= xs[i + 1] {
      return false
    }
    i += 1
  }
  true
}

///|
/// `forall_holds(xs, p)` —— 全称量化谓词：`xs` 中每个元素均满足 `p`。
/// 用于「BloomFilter 已插入元素必命中（无假阴性）」「range 结果键均在
/// 区间内」等逐元素性质。以 `Int` 编码元素（调用侧负责映射），保持谓词
/// 与具体容器类型解耦。纯、全函数（空序列平凡为真）。
pub fn forall_holds(xs : Array[Int], p : (Int) -> Bool) -> Bool {
  let mut i = 0
  while i < xs.length() {
    if !p(xs[i]) {
      return false
    }
    i += 1
  }
  true
}

///|
/// `same_members(xs, ys)` —— 集合外延相等谓词：双向包含（`xs ⊆ ys` 且
/// `ys ⊆ xs`，按值成员判定，忽略重数与次序）。用于 Roaring 并/交结果与
/// 参考模型（逐元素成员判定）的外延一致性等集合代数律。纯、全函数。
pub fn same_members(xs : Array[Int], ys : Array[Int]) -> Bool {
  subset_of(xs, ys) && subset_of(ys, xs)
}
