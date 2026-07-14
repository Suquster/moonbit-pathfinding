// Feature: championship-v1-upgrade, Property 29: 复杂度表完整、唯一、字段非空
//
// 本文件实现 Property 29（设计文档 §「Property 29: 复杂度表完整、唯一、
// 字段非空」/ Requirements 19.1, 19.2）的属性测试与确定性校验：
//   * algorithm_metadata() 恰好 33 条（algorithm_count = 30 经典 + CH/JPS/ALT）；
//   * 每个算法名唯一（无重复无遗漏）；
//   * 每条元数据的 5 个必填字段（name / worst_time / avg_time / space /
//     applicability）均非空（长度 > 0）。
//
// 复用共享 PBT 包 @infra_pbt 的 Gen / Rng / holds_for_all 模板，每条属性
// 迭代次数 ≥100（显式传入 iters=100，满足 Requirement 11.3 基线）。

///|
/// 统计字符串中换行符 '\n' 的数量，用于校验复杂度表的物理行数。
///
/// complexity_table 每输出一行都以 row_suffix（以 "\n" 结尾）收尾，因此
/// 换行符数量恰等于表格总行数：2 行表头（标题 + 对齐分隔）+ N 行数据。
fn cc_count_newlines(s : String) -> Int {
  let mut n = 0
  for c in s {
    if c == '\n' {
      n = n + 1
    }
  }
  n
}

///|
/// 校验一条元数据的 5 个必填字段是否全部非空（长度 > 0）。
fn cc_all_fields_nonblank(m : AlgoMeta) -> Bool {
  m.name.length() > 0 &&
  m.worst_time.length() > 0 &&
  m.avg_time.length() > 0 &&
  m.space.length() > 0 &&
  m.applicability.length() > 0
}

///|
/// 以 Fisher–Yates 洗牌对元数据数组做随机置换（用随机种子 rng 驱动）。
///
/// 置换不增减元素，仅打乱顺序，用于反复校验「行数 / 唯一性 / 非空」等
/// 不变量对元数据排列顺序保持稳定。
fn cc_shuffled_metadata(rng : @infra_pbt.Rng) -> Array[AlgoMeta] {
  let arr = algorithm_metadata()
  let n = arr.length()
  for i = n - 1; i > 0; i = i - 1 {
    let j = rng.next_below(i + 1)
    let tmp = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
  }
  arr
}

///|
/// 判断元数据数组中的算法名是否两两互异（无重复）。
fn cc_names_all_distinct(metas : Array[AlgoMeta]) -> Bool {
  let seen : Map[String, Bool] = Map([])
  for i = 0; i < metas.length(); i = i + 1 {
    let name = metas[i].name
    if seen.get(name) is Some(_) {
      return false
    }
    seen.set(name, true)
  }
  true
}

///|
/// Feature: championship-v1-upgrade, Property 29（确定性校验）：长度 / 唯一 / 非空
///
/// 确定性断言三项核心不变量：
///   1. algorithm_metadata() 长度恰为 algorithm_count（33）；
///   2. 所有算法名互异（无重复）；
///   3. 每条元数据的 5 个必填字段均非空。
///
/// **Validates: Requirements 19.1, 19.2**
test "Feature: championship-v1-upgrade, Property 29: metadata is complete, unique and non-blank (deterministic)" {
  let metas = algorithm_metadata()
  // (1) 总数恰为 33（以命名常量 algorithm_count 表达，单点维护）。
  @test.assert_eq(metas.length(), algorithm_count)
  @test.assert_eq(metas.length(), 33)
  // (2) 名称两两互异（无重复无遗漏）。
  assert_true(cc_names_all_distinct(metas))
  // (3) 每条 5 个字段全部非空。
  for i = 0; i < metas.length(); i = i + 1 {
    assert_true(cc_all_fields_nonblank(metas[i]))
  }
  // 附加：complexity_table 物化为 2 行表头 + 33 行数据 = 35 行。
  match complexity_table(metas) {
    Ok(table) => @test.assert_eq(cc_count_newlines(table), 35)
    Err(_) => abort("complexity_table 对合法 33 条元数据不应失败")
  }
}

///|
/// Feature: championship-v1-upgrade, Property 29（属性·随机索引对名称互异，≥100 迭代）
///
/// 对任意随机抽取的索引对 (i, j)（范围 [0, 33)），当 i ≠ j 时对应算法名必不相等。
/// 复用 @infra_pbt 的 holds_for_all 模板，显式迭代 100 次。
///
/// **Validates: Requirements 19.1, 19.2**
test "Feature: championship-v1-upgrade, Property 29: random distinct indices map to distinct names (holds_for_all template)" {
  let metas = algorithm_metadata()
  let n = metas.length()
  let gen_pair = @infra_pbt.Gen::new(fn(rng) {
    let i = rng.next_below(n)
    let j = rng.next_below(n)
    (i, j)
  })
  let ok = @infra_pbt.holds_for_all(
    gen_pair,
    fn(pair) {
      let (i, j) = pair
      // 同一索引天然相等，跳过；不同索引必须映射到不同名称。
      i == j || metas[i].name != metas[j].name
    },
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 29（属性·随机置换后不变量稳定，≥100 迭代）
///
/// 对任意随机置换后的 33 条元数据：
///   * 长度恒为 33（algorithm_count）；
///   * 名称仍两两互异；
///   * 每条 5 个字段仍非空；
///   * complexity_table 仍返回 Ok，且行数 = 33 + 2（表头）= 35。
/// 复用 @infra_pbt 的 holds_for_all 模板，显式迭代 100 次。
///
/// **Validates: Requirements 19.1, 19.2**
test "Feature: championship-v1-upgrade, Property 29: invariants hold under random permutation (holds_for_all template)" {
  let gen_perm = @infra_pbt.Gen::new(fn(rng) { cc_shuffled_metadata(rng) })
  let ok = @infra_pbt.holds_for_all(
    gen_perm,
    fn(metas) {
      let len_ok = metas.length() == algorithm_count
      let unique_ok = cc_names_all_distinct(metas)
      let mut fields_ok = true
      for i = 0; i < metas.length(); i = i + 1 {
        if !cc_all_fields_nonblank(metas[i]) {
          fields_ok = false
          break
        }
      }
      let table_ok = match complexity_table(metas) {
        Ok(table) => cc_count_newlines(table) == 35
        Err(_) => false
      }
      len_ok && unique_ok && fields_ok && table_ok
    },
    iters=100,
  )
  assert_true(ok)
}
