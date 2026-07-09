// compat_diff_test.mbt —— semver 兼容性 diff 流水线黑盒测试（G-A2）。
//
// 覆盖：三档位分类（删除/改签名 → MAJOR、新增 → MINOR、无变化 → PATCH）、
// 发布判定通过/违规诊断、非单调与非法版本拒绝、PBT（随机表面扰动的
// 档位单调性：任何含删除或改签名的 diff 必为 MAJOR）。

///|
fn surface_v1() -> @release_aggregate.ApiSurface {
  @release_aggregate.ApiSurface::new([
    ("sha256", "fn sha256(Array[Int]) -> Array[Int]"),
    ("crc32", "fn crc32(Array[Int]) -> UInt"),
    ("deflate", "fn deflate(Array[Int]) -> Array[Int]"),
  ])
}

///|
test "compat_diff 三档位分类" {
  // 无变化 → PATCH。
  let same = @release_aggregate.compat_diff(surface_v1(), surface_v1())
  assert_true(same.required == @release_aggregate.PatchBump)
  assert_eq(same.breaking().length(), 0)
  // 仅新增 → MINOR。
  let added = @release_aggregate.ApiSurface::new([
    ("sha256", "fn sha256(Array[Int]) -> Array[Int]"),
    ("crc32", "fn crc32(Array[Int]) -> UInt"),
    ("deflate", "fn deflate(Array[Int]) -> Array[Int]"),
    ("zstd_compress", "fn zstd_compress(Array[Int], Bool) -> Array[Int]"),
  ])
  let d_add = @release_aggregate.compat_diff(surface_v1(), added)
  assert_true(d_add.required == @release_aggregate.MinorBump)
  assert_eq(d_add.added.length(), 1)
  // 删除 + 改签名 → MAJOR。
  let broken = @release_aggregate.ApiSurface::new([
    ("sha256", "fn sha256(Bytes) -> Bytes"),
    ("deflate", "fn deflate(Array[Int]) -> Array[Int]"),
  ])
  let d_break = @release_aggregate.compat_diff(surface_v1(), broken)
  assert_true(d_break.required == @release_aggregate.MajorBump)
  assert_eq(d_break.removed.length(), 1)
  assert_eq(d_break.changed.length(), 1)
  assert_eq(d_break.breaking().length(), 2)
}

///|
test "check_release_compat 发布判定与诊断" {
  let v1 = surface_v1()
  // 无变化 + PATCH 升级 → 通过。
  assert_true(
    @release_aggregate.check_release_compat(v1, v1, "1.2.3", "1.2.4") is None,
  )
  // 破坏性变更 + MAJOR 升级 → 通过。
  let broken = @release_aggregate.ApiSurface::new([
    ("crc32", "fn crc32(Array[Int]) -> UInt"),
  ])
  assert_true(
    @release_aggregate.check_release_compat(v1, broken, "1.2.3", "2.0.0")
    is None,
  )
  // 破坏性变更 + 仅 MINOR 升级 → 违规且给出见证。
  match @release_aggregate.check_release_compat(v1, broken, "1.2.3", "1.3.0") {
    Some(msg) => assert_true(msg.contains("MAJOR"))
    None => assert_true(false)
  }
  // 新增 API + 仅 PATCH 升级 → 违规。
  let added = @release_aggregate.ApiSurface::new([
    ("sha256", "fn sha256(Array[Int]) -> Array[Int]"),
    ("crc32", "fn crc32(Array[Int]) -> UInt"),
    ("deflate", "fn deflate(Array[Int]) -> Array[Int]"),
    ("extra", "fn extra() -> Unit"),
  ])
  match @release_aggregate.check_release_compat(v1, added, "1.2.3", "1.2.4") {
    Some(msg) => assert_true(msg.contains("MINOR"))
    None => assert_true(false)
  }
  // 非单调版本 → 拒绝。
  assert_true(
    @release_aggregate.check_release_compat(v1, v1, "1.2.3", "1.2.3") is Some(_),
  )
  // 非法版本 → 拒绝。
  assert_true(
    @release_aggregate.check_release_compat(v1, v1, "v1.2", "1.3.0") is Some(_),
  )
}

///|
test "actual_bump 档位判定" {
  assert_true(
    @release_aggregate.actual_bump("1.2.3", "2.0.0") ==
    Some(@release_aggregate.MajorBump),
  )
  assert_true(
    @release_aggregate.actual_bump("1.2.3", "1.3.0") ==
    Some(@release_aggregate.MinorBump),
  )
  assert_true(
    @release_aggregate.actual_bump("1.2.3", "1.2.4") ==
    Some(@release_aggregate.PatchBump),
  )
  assert_true(@release_aggregate.actual_bump("1.2.3", "1.2.3") is None)
  assert_true(@release_aggregate.actual_bump("1.2.3", "0.9.9") is None)
}

///|
test "PBT：随机表面扰动的档位正确性（100 迭代）" {
  let gen : @infra_pbt.Gen[(Array[(String, String)], Int, Int)] = @infra_pbt.Gen::new(fn(
      rng,
    ) {
      let n = 1 + rng.next_below(10)
      let entries : Array[(String, String)] = []
      for i in 0..<n {
        entries.push(
          ("decl" + i.to_string(), "sig" + rng.next_below(3).to_string()),
        )
      }
      // 扰动模式：0 = 恒等，1 = 仅新增，2 = 删除一个，3 = 改一个签名。
      (entries, rng.next_below(4), rng.next_below(n))
    },
  )
  let ok = @infra_pbt.holds_for_all(gen, fn(case) {
    let (entries, mode, pick) = case
    let old_api = @release_aggregate.ApiSurface::new(entries)
    let mutated : Array[(String, String)] = []
    for k in 0..<entries.length() {
      let (name, sig) = entries[k]
      if mode == 2 && k == pick {
        continue
      }
      if mode == 3 && k == pick {
        mutated.push((name, sig + "'"))
      } else {
        mutated.push((name, sig))
      }
    }
    if mode == 1 {
      mutated.push(("brand_new_decl", "sig"))
    }
    let diff = @release_aggregate.compat_diff(
      old_api,
      @release_aggregate.ApiSurface::new(mutated),
    )
    match mode {
      0 => diff.required == @release_aggregate.PatchBump
      1 => diff.required == @release_aggregate.MinorBump
      _ => diff.required == @release_aggregate.MajorBump
    }
  })
  assert_true(ok)
}

///|
test "check_release_compat：新增 API 配 MINOR 升级即合规" {
  let old_api = @release_aggregate.ApiSurface::new([("f", "sig")])
  let new_api = @release_aggregate.ApiSurface::new([("f", "sig"), ("g", "sig2")])
  assert_true(
    @release_aggregate.check_release_compat(old_api, new_api, "1.2.3", "1.3.0")
    is None,
  )
  // 新增 API 配 MAJOR 升级同样覆盖（更高档位覆盖低要求）。
  assert_true(
    @release_aggregate.check_release_compat(old_api, new_api, "1.2.3", "2.0.0")
    is None,
  )
}
