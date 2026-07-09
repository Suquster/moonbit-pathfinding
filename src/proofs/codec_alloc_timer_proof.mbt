// codec_alloc_timer_proof.mbt —— INFRA 家族第四批证明谓词：编解码
// （infra_codec：CBOR/CSV/hex/UTF-8/varint）、分配器（infra_alloc：Slab
// 世代键生命周期）与定时器（infra_timer：TimerWheel 触发守恒）的不变量接入。
//
// 复用约定：与其余 `*_proof.mbt` 相同——每条不变量编码为纯、全（total）的
// `Bool` 谓词，proofs 生产代码不引入新依赖（仅 @core），跨包驱动只发生在
// 测试期（codec_alloc_timer_proof_test.mbt 以真实包实现接地）。
//
// 覆盖的不变量家族：
//   * 往返恒等（CBOR/CSV/hex/UTF-8/varint/zigzag，复用 round_trip_eq）；
//   * 句柄唯一（同时存活的 Slab 键 / TimerWheel 定时器 id 两两互异）；
//   * 集合包含（实际触发的定时器 id ⊆ 已调度且未取消的 id 集）；
//   * 计数守恒（触发 + 取消 + 待决 == 已调度总数，复用 count_conserved）。

///|
/// `all_distinct(xs)` —— 句柄唯一性谓词：序列中任意两个元素互异。用于
/// 「同时存活的 Slab 键两两不同」「TimerWheel 分配的定时器 id 不复用」等
/// 无别名（no-aliasing）不变量。O(n²) 逐对比较，保持纯、全且零依赖；
/// 证据规模由调用侧生成器控制（≤ 数百元素）。空序列与单元素平凡为真。
pub fn all_distinct(xs : Array[Int]) -> Bool {
  let mut i = 0
  while i < xs.length() {
    let mut j = i + 1
    while j < xs.length() {
      if xs[i] == xs[j] {
        return false
      }
      j += 1
    }
    i += 1
  }
  true
}

///|
/// `subset_of(xs, ys)` —— 集合包含谓词：`xs` 的每个元素都出现在 `ys` 中
/// （按值成员判定，忽略重数与次序）。用于「实际触发的定时器 id 必然来自
/// 已调度集合」「iter_live 的键 ⊆ 历史 alloc 的键」等来源封闭不变量。
/// 纯、全函数（空 `xs` 平凡为真）。
pub fn subset_of(xs : Array[Int], ys : Array[Int]) -> Bool {
  let mut i = 0
  while i < xs.length() {
    let mut found = false
    let mut j = 0
    while j < ys.length() {
      if ys[j] == xs[i] {
        found = true
        break
      }
      j += 1
    }
    if !found {
      return false
    }
    i += 1
  }
  true
}
