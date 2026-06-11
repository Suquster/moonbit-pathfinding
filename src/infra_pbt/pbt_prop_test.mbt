// pbt_prop_test.mbt —— infra_pbt 自身的属性测试（task 1.2）。
//
// 承接 pbt_test.mbt 的单元测试，本文件以属性（property）形式校验 infra_pbt
// 基础设施的两条核心不变量：
//
//   1. Rng 同种子产生逐位一致序列（确定性）。这是三后端逐位一致性
//      （Requirement 11.1）的基石：`Rng` 的 xorshift64 仅由移位与异或构成，
//      不含可能因后端整数语义差异而分歧的加法/乘法，因此对同一种子在
//      `wasm-gc` / `native` / `js` 上产生相同序列。本文件的属性测试在三后端
//      矩阵下运行同一断言，任一后端的分歧都会使对应 run 失败（由 CI 矩阵承载
//      差分校验）。
//   2. holds_for_all 默认迭代次数为 100（Requirement 11.2 / 11.3 质量门禁基线）。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`。

///|
/// Feature: moonbit-infra-suite, Property 1.2a: Rng 同种子逐位一致（确定性）
///
/// 对任意种子，两个由同一种子构造的 Rng 实例在连续推进中产生逐位一致的
/// 64 位序列。该确定性是三后端一致性（Requirement 11.1）的前提条件。
///
/// **Validates: Requirements 11.1, 11.2**
test "Feature: moonbit-infra-suite, Property 1.2a: rng same seed bit-identical" {
  // 以 100 个不同种子（默认迭代次数）作为输入空间，逐一校验确定性。
  let seed_gen = gen_int_range(1, 1_000_000)
  let ok = holds_for_all(seed_gen, fn(s) {
    let seed = s.to_uint64()
    let a = rng_new(seed)
    let b = rng_new(seed)
    let mut i = 0
    while i < 32 {
      if a.next() != b.next() {
        return false
      }
      i = i + 1
    }
    true
  })
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 1.2b: 同种子重建后序列仍一致
///
/// 对任意种子，先推进一个 Rng 若干步，再用同一种子新建一个 Rng，新实例
/// 从头产生的序列必须与首个实例从头产生的序列逐位一致（可重放性）。
///
/// **Validates: Requirements 11.1, 11.2**
test "Feature: moonbit-infra-suite, Property 1.2b: rng replayable from seed" {
  let seed_gen = gen_int_range(1, 1_000_000)
  let ok = holds_for_all(seed_gen, fn(s) {
    let seed = s.to_uint64()
    // 首次运行：记录前 16 个输出。
    let first = rng_new(seed)
    let recorded = []
    let mut i = 0
    while i < 16 {
      recorded.push(first.next())
      i = i + 1
    }
    // 重放：同种子新建，逐位比对。
    let replay = rng_new(seed)
    let mut j = 0
    while j < 16 {
      if replay.next() != recorded[j] {
        return false
      }
      j = j + 1
    }
    true
  })
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 1.2c: holds_for_all 默认迭代 100 次
///
/// holds_for_all 在未显式提供 `iters~` 时，应恰好调用谓词 `default_iters`
/// （100）次，满足 Requirement 11.2 / 11.3 的"每条属性测试最少 100 次迭代"
/// 质量门禁基线。
///
/// **Validates: Requirements 11.2**
test "Feature: moonbit-infra-suite, Property 1.2c: holds_for_all default iteration count" {
  // 用单元素数组充当可变计数器，统计谓词被调用的次数。
  let calls = [0]
  let g = gen_int_range(0, 100)
  let ok = holds_for_all(g, fn(_x) {
    calls[0] = calls[0] + 1
    true
  })
  assert_true(ok)
  assert_eq(default_iters, 100)
  assert_eq(calls[0], 100)
  assert_eq(calls[0], default_iters)
}

///|
/// holds_for_all 在显式提供 `iters~` 时，应恰好按给定次数迭代（与默认值对照）。
///
/// **Validates: Requirements 11.2**
test "Feature: moonbit-infra-suite, Property 1.2c': holds_for_all respects explicit iters" {
  let calls = [0]
  let g = gen_int_range(0, 100)
  let _ = holds_for_all(
    g,
    fn(_x) {
      calls[0] = calls[0] + 1
      true
    },
    iters=37,
  )
  assert_eq(calls[0], 37)
}

///|
/// Feature: moonbit-infra-suite, Property 1.2d: Rng 黄金序列（三后端快照）
///
/// 固定种子的前若干 64 位输出作为黄金快照。UInt64 的移位/异或语义在三后端
/// 应完全一致，故该快照在 `wasm-gc` / `native` / `js` 上必须匹配；任一后端
/// 计算分歧都会使快照不一致 → 对应 CI run 失败（Requirement 11.1 差分门禁）。
///
/// **Validates: Requirements 11.1**
test "Feature: moonbit-infra-suite, Property 1.2d: rng golden sequence snapshot" {
  let r = rng_new(0x9E3779B97F4A7C15)
  // 将固定种子的前 4 个 64 位输出连成单一字符串作为黄金快照：
  // 既避免 UInt64 的 Show 弃用告警，又使三后端比对一目了然。
  let parts : Array[String] = []
  let mut i = 0
  while i < 4 {
    parts.push(r.next().to_string())
    i = i + 1
  }
  let golden = parts.join(",")
  inspect(
    golden,
    content="15860402102123842989,7273575876580499574,8865281517519135030,3485510186621062260",
  )
}
