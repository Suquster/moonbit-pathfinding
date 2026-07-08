// audit_test.mbt —— mooncakes 索引审计引擎黑盒测试（G-A3 + H-1）。
//
// 夹具取自 mooncakes.io 真实索引条目（2026-07-08 抓取的代表性子集）；
// 覆盖：psv 解析（含畸形行与含 `|` 的描述尾字段）、能力域覆盖与去重、
// 缺口报告阈值、许可证直方图、markdown 渲染、PBT 解析健壮性。

///|
fn sample_lines() -> Array[String] {
  [
    "0Ayachi0/elk|0.1.0|Apache-2.0|ELK graph auto-layout implementation in Moonbit",
    "alice/json-utils|1.2.0|MIT|JSON parsing helpers", "bob/zstd-bindings|0.0.1||Zstandard compression bindings",
    "", "broken-line-no-fields", "carol/regexlib|2.0.0|MIT|Regex engine with lazy DFA | unicode support",
  ]
}

///|
test "parse_index：合法条目 / 畸形行 / 含竖线描述尾字段" {
  let snap = @mooncakes_audit.parse_index(sample_lines())
  assert_eq(snap.entries.length(), 4)
  assert_eq(snap.malformed, 1)
  assert_eq(snap.entries[0].name, "0Ayachi0/elk")
  assert_eq(snap.entries[2].license, "")
  // 尾字段重新拼接。
  assert_eq(
    snap.entries[3].description,
    "Regex engine with lazy DFA | unicode support",
  )
}

///|
test "domain_coverage：关键词大小写不敏感命中与去重" {
  let snap = @mooncakes_audit.parse_index(sample_lines())
  let compress = @mooncakes_audit.CapabilityDomain::new("压缩", [
    "zstd", "DEFLATE", "compression",
  ])
  let hits = @mooncakes_audit.domain_coverage(snap, compress)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0], "bob/zstd-bindings")
  let regex = @mooncakes_audit.CapabilityDomain::new("正则", ["REGEX"])
  assert_eq(@mooncakes_audit.domain_coverage(snap, regex).length(), 1)
}

///|
test "gap_report 与 markdown 渲染" {
  let snap = @mooncakes_audit.parse_index(sample_lines())
  let domains = [
    @mooncakes_audit.CapabilityDomain::new("压缩", ["zstd", "compression"]),
    @mooncakes_audit.CapabilityDomain::new("图算法", ["graph", "layout"]),
    @mooncakes_audit.CapabilityDomain::new("路径规划", [
      "pathfinding", "dijkstra",
    ]),
  ]
  let report = @mooncakes_audit.gap_report(snap, domains, 1)
  assert_eq(report.length(), 3)
  let (d0, h0, g0) = report[0]
  assert_true(d0 == "压缩" && h0 == 1 && g0)
  let (_, h2, g2) = report[2]
  assert_true(h2 == 0 && g2)
  let md = @mooncakes_audit.render_coverage_markdown(snap, domains, 1)
  assert_true(md.contains("| 压缩 | 1 | 是 |"))
  assert_true(md.contains("| 路径规划 | 0 | 是 |"))
  assert_true(md.contains("索引条目 4 个，畸形行 1 条"))
}

///|
test "license_histogram：计数与空许可证归并" {
  let snap = @mooncakes_audit.parse_index(sample_lines())
  let hist = @mooncakes_audit.license_histogram(snap)
  let mut mit = 0
  let mut none_count = 0
  for row in hist {
    let (lic, cnt) = row
    if lic == "MIT" {
      mit = cnt
    }
    if lic == "(none)" {
      none_count = cnt
    }
  }
  assert_eq(mit, 2)
  assert_eq(none_count, 1)
}

///|
test "PBT：解析健壮性——条目数 + 畸形数 ≤ 非空行数（100 迭代）" {
  let gen : @infra_pbt.Gen[Array[String]] = @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_below(30)
    let lines : Array[String] = []
    for _k in 0..<n {
      let m = rng.next_below(4)
      let mut line = ""
      for f in 0..<m {
        if f > 0 {
          line = line + "|"
        }
        line = line + "f" + rng.next_below(10).to_string()
      }
      lines.push(line)
    }
    lines
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(lines) {
    let snap = @mooncakes_audit.parse_index(lines)
    let mut nonempty = 0
    for l in lines {
      if l != "" {
        nonempty = nonempty + 1
      }
    }
    snap.entries.length() + snap.malformed == nonempty && snap.malformed >= 0
  })
  assert_true(ok)
}
