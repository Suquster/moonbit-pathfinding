// release_audit_proof_test.mbt —— 发布元数据/生态审计/证据索引家族的
// 证明谓词真实实现接地测试（INFRA 第八批）。
//
// 以 @release_meta / @mooncakes_audit / @evidence_index 的真实包实现驱动
// 既有谓词库（跨包驱动只发生在测试期）：
//   * release_meta：parse_semver 与 is_valid_semver 判定一致（随机字符串
//     PBT）；aggregate_release_ready 与三门禁合取律逐真值表一致；
//   * evidence_index：合法行解析后 is_sound、render_markdown 包含全部
//     claim（contains_all 复用）、digest 确定性；
//   * mooncakes_audit：license_histogram 计数守恒（count_conserved 复用）、
//     domain_coverage 来源封闭（subset_of 复用）。

// --- release_meta：判定一致 + 合取律 ---

///|
/// 随机疑似版本串生成器（混合合法/非法形态，覆盖判定边界）。
fn ra_version_gen() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    let parts = ["0", "1", "12", "007", "x", "", "3a"]
    let seps = [".", "", "-"]
    let a = parts[rng.next_range(0, 6)]
    let b = parts[rng.next_range(0, 6)]
    let c = parts[rng.next_range(0, 6)]
    let s1 = seps[rng.next_range(0, 2)]
    let s2 = seps[rng.next_range(0, 2)]
    a + s1 + b + s2 + c
  })
}

///|
test "parse_semver succeeds iff is_valid_semver holds" {
  let ok = @infra_pbt.holds_for_all(
    ra_version_gen(),
    fn(s : String) -> Bool {
      let parsed = @release_meta.parse_semver(s) is Some(_)
      parsed == @release_meta.is_valid_semver(s)
    },
    iters=200,
  )
  assert_true(ok)
}

///|
test "aggregate_release_ready agrees with the three-gate conjunction law" {
  for t in [true, false] {
    for p in [true, false] {
      for d in [true, false] {
        let gates : @release_meta.QualityGates = {
          tests_passing: t,
          proofs_passing: p,
          docs_passing: d,
        }
        assert_true(
          @release_meta.aggregate_release_ready(gates) == (t && p && d),
        )
        assert_true(@release_meta.release_ready_of(t, p, d) == (t && p && d))
      }
    }
  }
}

// --- evidence_index：健全性 + 渲染完备 + 摘要确定性 ---

///|
test "evidence index is sound, renders all claims, and digests deterministically" {
  let rows = [
    "断言甲|src/core::predicates.mbt|abc1234", "断言乙|src/proofs::ds_proof.mbt|def5678",
    "断言丙|src/graph::csr_test.mbt|0123abc",
  ]
  let idx = @evidence_index.parse_evidence(rows)
  assert_true(idx.is_sound())
  let md = idx.render_markdown()
  assert_true(contains_all(md, ["断言甲", "断言乙", "断言丙"]))
  // 摘要确定性：同一输入两次解析摘要一致。
  assert_true(idx.digest() == @evidence_index.parse_evidence(rows).digest())
}

// --- mooncakes_audit：计数守恒 + 来源封闭 ---

///|
test "license histogram conserves package count and coverage is source-closed" {
  let lines = [
    "pkg-a|1.0.0|Apache-2.0|graph algorithms", "pkg-b|0.2.1|MIT|priority queue",
    "pkg-c|2.0.0|Apache-2.0|csv codec", "pkg-d|0.9.9|MIT|regex engine",
  ]
  let snap = @mooncakes_audit.parse_index(lines)
  // 计数守恒：直方图各桶之和 == 条目总数。
  let counts : Array[Int] = []
  for bucket in @mooncakes_audit.license_histogram(snap) {
    counts.push(bucket.1)
  }
  assert_true(count_conserved(snap.entries.length(), counts))
  // 来源封闭：域覆盖返回的包名 ⊆ 快照条目名（以驻留下标编码比较）。
  let domain = @mooncakes_audit.CapabilityDomain::new("text", ["regex", "csv"])
  let covered = @mooncakes_audit.domain_coverage(snap, domain)
  let all_names : Array[String] = []
  for e in snap.entries {
    all_names.push(e.name)
  }
  let covered_ids : Array[Int] = []
  for c in covered {
    let mut idx = -1
    let mut i = 0
    while i < all_names.length() {
      if all_names[i] == c {
        idx = i
      }
      i += 1
    }
    covered_ids.push(idx)
  }
  let universe : Array[Int] = []
  for i in 0..<all_names.length() {
    universe.push(i)
  }
  assert_true(subset_of(covered_ids, universe))
}
