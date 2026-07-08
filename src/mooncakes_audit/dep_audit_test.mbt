// dep_audit_test.mbt —— 依赖健康审计黑盒测试（H-2）。
//
// 覆盖：四类发现（健康/缺失/版本落后/许可证不合规）、优先级顺序、
// 宽松版本解析（1..3 段）、整体健康一票否决、markdown 渲染、PBT
// （版本序反对称：a<b 与 b<a 不同真）。

///|
fn dep_index() -> @mooncakes_audit.IndexSnapshot {
  @mooncakes_audit.parse_index([
    "alice/json|1.2.0|MIT|JSON utils", "bob/zstd|0.3.1|Apache-2.0|Zstandard bindings",
    "carol/gpl-lib|2.0.0|GPL-3.0|copyleft library", "dave/nolicense|1.0.0||no license declared",
  ])
}

///|
test "audit_dep：四类发现与优先级" {
  let snap = dep_index()
  let allowed = ["MIT", "Apache-2.0"]
  // 健康：存在、许可合规、版本最新。
  assert_true(
    @mooncakes_audit.audit_dep(
      snap,
      @mooncakes_audit.DepRequirement::new("alice/json", "1.2.0"),
      allowed,
    ) ==
    @mooncakes_audit.DepHealthy,
  )
  // 索引缺失。
  assert_true(
    @mooncakes_audit.audit_dep(
      snap,
      @mooncakes_audit.DepRequirement::new("ghost/pkg", "1.0.0"),
      allowed,
    ) ==
    @mooncakes_audit.DepMissingFromIndex,
  )
  // 版本落后（声明 0.2 < 最新 0.3.1，宽松两段解析）。
  assert_true(
    @mooncakes_audit.audit_dep(
      snap,
      @mooncakes_audit.DepRequirement::new("bob/zstd", "0.2"),
      allowed,
    ) ==
    @mooncakes_audit.DepVersionBehind("0.3.1"),
  )
  // 许可证不合规优先于版本检查。
  assert_true(
    @mooncakes_audit.audit_dep(
      snap,
      @mooncakes_audit.DepRequirement::new("carol/gpl-lib", "1.0.0"),
      allowed,
    ) ==
    @mooncakes_audit.DepLicenseViolation("GPL-3.0"),
  )
  // 空许可证归 "(none)"。
  assert_true(
    @mooncakes_audit.audit_dep(
      snap,
      @mooncakes_audit.DepRequirement::new("dave/nolicense", "1.0.0"),
      allowed,
    ) ==
    @mooncakes_audit.DepLicenseViolation("(none)"),
  )
}

///|
test "audit_deps 整体健康一票否决与 markdown 渲染" {
  let snap = dep_index()
  let allowed = ["MIT", "Apache-2.0"]
  let deps = [
    @mooncakes_audit.DepRequirement::new("alice/json", "1.2.0"),
    @mooncakes_audit.DepRequirement::new("bob/zstd", "0.3.1"),
  ]
  let (findings, healthy) = @mooncakes_audit.audit_deps(snap, deps, allowed)
  assert_eq(findings.length(), 2)
  assert_true(healthy)
  let bad = [
    @mooncakes_audit.DepRequirement::new("alice/json", "1.2.0"),
    @mooncakes_audit.DepRequirement::new("ghost/pkg", "1.0.0"),
  ]
  let (_, healthy2) = @mooncakes_audit.audit_deps(snap, bad, allowed)
  assert_true(!healthy2)
  let md = @mooncakes_audit.render_dep_audit_markdown(snap, bad, allowed)
  assert_true(
    md.contains("| ghost/pkg | 索引缺失（下架/改名风险） |"),
  )
  assert_true(md.contains("整体健康：不通过"))
}

///|
test "PBT：随机版本对的时效判定自洽（100 迭代）" {
  let gen : @infra_pbt.Gen[(Int, Int, Int, Int, Int, Int)] = @infra_pbt.Gen::new(fn(
      rng,
    ) {
      (
        rng.next_below(5),
        rng.next_below(5),
        rng.next_below(5),
        rng.next_below(5),
        rng.next_below(5),
        rng.next_below(5),
      )
    },
  )
  let ok = @infra_pbt.holds_for_all(gen, fn(c) {
    let (a0, a1, a2, b0, b1, b2) = c
    let va = a0.to_string() + "." + a1.to_string() + "." + a2.to_string()
    let vb = b0.to_string() + "." + b1.to_string() + "." + b2.to_string()
    let snap = @mooncakes_audit.parse_index(["p/x|" + vb + "|MIT|lib"])
    let f = @mooncakes_audit.audit_dep(
      snap,
      @mooncakes_audit.DepRequirement::new("p/x", va),
      ["MIT"],
    )
    let behind = a0 < b0 ||
      (a0 == b0 && a1 < b1) ||
      (a0 == b0 && a1 == b1 && a2 < b2)
    if behind {
      f == @mooncakes_audit.DepVersionBehind(vb)
    } else {
      f == @mooncakes_audit.DepHealthy
    }
  })
  assert_true(ok)
}
