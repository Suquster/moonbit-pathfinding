// Feature: championship-v1-upgrade, Property 21: PathError 诊断消息非空且唯一标识变体
//
// 本文件以属性测试（property-based test）校验 `@graph.PathError::message()`
// 的两条核心不变量（design.md §「Property 21」/ Requirement 13.7）：
//
//   1. **非空**：对任意 `PathError` 变体，`message()` 返回长度大于 0 的字符串。
//   2. **变体唯一可辨**：不同变体（枚举构造子）的诊断消息两两互异，从而可由
//      消息内容唯一反推其所属失败原因。注意「变体」指枚举构造子层面：两个
//      `InvalidArgument` 携带不同细节属于同一变体，不要求其消息互异（事实上
//      它们仍因细节不同而不同，但属性只约束「不同变体」之间互异）。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。迭代次数取 256（远超 ≥100 基线）。

///|
/// 返回 `PathError` 的「变体索引」：同一构造子映射到同一索引。
///
/// 该索引用于在属性中区分「同变体」与「异变体」——只有异变体之间才被要求
/// 诊断消息互异。
fn p21_kind_index(e : PathError) -> Int {
  match e {
    SourceNotFound => 0
    TargetNotFound => 1
    Unreachable => 2
    NegativeCycle => 3
    InvalidArgument(_) => 4
  }
}

///|
/// 五个变体各取一个「规范代表」实例，用于异变体互异性的两两比对基准。
///
/// `InvalidArgument` 以空细节作为规范代表；其消息因固定前缀而仍与其余四个
/// 变体互异（见 `path_error.mbt` 的 `message()` 设计说明）。
fn p21_canonical() -> Array[PathError] {
  [
    SourceNotFound,
    TargetNotFound,
    Unreachable,
    NegativeCycle,
    InvalidArgument(""),
  ]
}

///|
/// 生成一段长度 0..7 的可见 ASCII（码位 33..125）细节串，用于 `InvalidArgument`。
///
/// 经 `Char::from_int` 在运行期构造字符，覆盖含空串在内的多样细节输入，以
/// 强化「无论细节为何，前缀都保证与其余变体互异」这一性质的检验强度。
fn p21_gen_detail(rng : @infra_pbt.Rng) -> String {
  let len = rng.next_below(8) // 细节长度 0..7（含空串）
  let sb = StringBuilder::new()
  let mut i = 0
  while i < len {
    let code = rng.next_range(33, 125) // 可见 ASCII 区间，避开控制字符
    sb.write_char(code.unsafe_to_char())
    i = i + 1
  }
  sb.to_string()
}

///|
/// 在五个变体上等概率取样的 `PathError` 生成器；`InvalidArgument` 携带随机细节。
fn p21_gen() -> @infra_pbt.Gen[PathError] {
  @infra_pbt.Gen::new(fn(rng) {
    match rng.next_below(5) {
      0 => SourceNotFound
      1 => TargetNotFound
      2 => Unreachable
      3 => NegativeCycle
      _ => InvalidArgument(p21_gen_detail(rng))
    }
  })
}

///|
/// Feature: championship-v1-upgrade, Property 21: PathError 诊断消息非空且唯一标识变体
///
/// 对任意随机生成的 `PathError`：
///   * 其 `message()` 非空；且
///   * 其消息与所有「不同变体」的规范代表消息两两互异（可唯一标识失败原因）。
///
/// 同时以确定性断言固定五个规范代表的消息互为不同，作为属性的基准锚点。
///
/// **Validates: Requirements 13.7**
test "Feature: championship-v1-upgrade, Property 21: patherror message non-empty and uniquely identifies variant" {
  let canonical = p21_canonical()
  // 锚点：五个规范代表的消息均非空且两两互异。
  let mut a = 0
  while a < canonical.length() {
    assert_true(canonical[a].message().length() > 0)
    let mut b = a + 1
    while b < canonical.length() {
      assert_true(canonical[a].message() != canonical[b].message())
      b = b + 1
    }
    a = a + 1
  }
  // 属性：随机变体（InvalidArgument 含随机细节）的消息非空，且与所有异变体
  // 规范代表互异。迭代 256 次（≥100 基线）。
  let ok = @infra_pbt.holds_for_all(
    p21_gen(),
    fn(err) {
      let msg = err.message()
      // 不变量 1：非空。
      if msg.length() == 0 {
        return false
      }
      // 不变量 2：与所有不同变体的诊断消息互异。
      let k = p21_kind_index(err)
      let reps = p21_canonical()
      let mut i = 0
      while i < reps.length() {
        if i != k && msg == reps[i].message() {
          return false
        }
        i = i + 1
      }
      true
    },
    iters=256,
  )
  assert_true(ok)
}
