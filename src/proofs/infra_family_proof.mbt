// infra_family_proof.mbt —— INFRA 家族（hash / compress / regex 引擎扩展）
// 的证明谓词全量接入（G-B4）。
//
// 复用约定：与其余 `*_proof.mbt` 相同——每条不变量编码为纯、全（total）的
// `Bool` 谓词，运行时由属性测试以真实包实现驱动（proofs 生产代码不引入
// 新依赖，跨包驱动只发生在测试期），`moon prove` 注解成熟后可原样引用。
//
// 覆盖的不变量家族：
//   * 往返恒等（压缩/编码/流式哈希 vs 一次性哈希）；
//   * 前缀封闭（zstd 帧以魔数开头，deflate/gzip 头合法）；
//   * 预算有界（有界回溯步数硬上界、解压炸弹上限）；
//   * 判定一致（多引擎差分：结果相等谓词）。

///|
/// 往返恒等：`decoded` 恰为 `original`（逐元素）。压缩 / 编解码 / 序列化
/// 的核心后置条件；`decode(encode(x)) == Some(x)` 的相等半边。纯、全。
pub fn bytes_round_trip_eq(original : Array[Int], decoded : Array[Int]) -> Bool {
  if original.length() != decoded.length() {
    return false
  }
  let mut i = 0
  while i < original.length() {
    if original[i] != decoded[i] {
      return false
    }
    i += 1
  }
  true
}

///|
/// 前缀封闭：`data` 以 `magic` 为前缀。容器格式（zstd/gzip 帧）的
/// 结构性后置条件——编码器输出必以格式魔数开头。纯、全。
pub fn has_magic_prefix(data : Array[Int], magic : Array[Int]) -> Bool {
  if data.length() < magic.length() {
    return false
  }
  let mut i = 0
  while i < magic.length() {
    if data[i] != magic[i] {
      return false
    }
    i += 1
  }
  true
}

///|
/// 预算有界：观测值 `observed` 不超过声明上界 `bound`（bound ≥ 0）。
/// 有界回溯步数、解压输出长度、缓存物化状态数的共同后置条件。纯、全。
pub fn within_budget(observed : Int, bound : Int) -> Bool {
  bound >= 0 && observed >= 0 && observed <= bound
}

///|
/// 判定一致：两引擎对同一输入给出的可选区间结果逐字段相等。
/// 多引擎差分（Pike VM / 有界回溯 / DFA 家族）的核心不变量。纯、全。
pub fn spans_agree(a : (Int, Int)?, b : (Int, Int)?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => {
      let (xs, xe) = x
      let (ys, ye) = y
      xs == ys && xe == ye
    }
    _ => false
  }
}

///|
/// 流式 / 一次性一致：分片累计计算的摘要与整体一次计算的摘要相等
/// （以字节数组表示）。流式哈希 API（Go `hash.Hash` 语义）的后置条件。纯、全。
pub fn streaming_matches_oneshot(
  streamed : Array[Int],
  oneshot : Array[Int],
) -> Bool {
  bytes_round_trip_eq(streamed, oneshot)
}
