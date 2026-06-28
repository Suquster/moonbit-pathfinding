// release_aggregate_test.mbt —— 全方向 release-ready 聚合门禁测试（任务 18.1）。
//
// 覆盖（Requirement 11.6）：
//   * 全部方向门禁全绿 → 整体 release-ready；
//   * 任一方向任一门禁未绿 → 整体不就绪（且其余方向仍各自就绪）；
//   * 聚合清单恰好含全部 10 个方向，且方向身份（名称）齐备无重复；
//   * 空清单不就绪的边界保护。

///|
/// 构造「三项门禁均为给定布尔」的 QualityGates。
fn gates_of(v : Bool) -> @release_meta.QualityGates {
  { tests_passing: v, proofs_passing: v, docs_passing: v }
}

///|
/// 构造「全部 10 个方向共用同一 QualityGates」的 SuiteGates。
fn uniform_suite_gates(g : @release_meta.QualityGates) -> SuiteGates {
  {
    parser_combinator: g,
    regex_engine: g,
    serialization: g,
    build_tool: g,
    logging: g,
    codegen_infra: g,
    dst: g,
    lsp: g,
    mini_compiler: g,
    actor: g,
  }
}

///|
/// 全绿：全部方向门禁通过时，整体进入 release-ready，且清单含 10 个方向、
/// 每个方向各自就绪。
test "aggregate_suite is ready when all directions are green" {
  let report = aggregate_suite(uniform_suite_gates(gates_of(true)))
  assert_true(report.release_ready)
  @test.assert_eq(report.directions.length(), direction_count)
  for d in report.directions {
    assert_true(d.release_ready)
  }
}

///|
/// 任一未绿：单个方向的单项门禁未通过即令整体不就绪；该方向自身不就绪，
/// 其余 9 个方向仍各自就绪（验证「逐方向独立 + 全方向合取」语义）。
test "aggregate_suite blocks release when any direction gate fails" {
  let green = gates_of(true)
  // 仅 dst 方向的可执行文档门禁未通过，其余全部全绿。
  let gates : SuiteGates = {
    ..uniform_suite_gates(green),
    dst: { tests_passing: true, proofs_passing: true, docs_passing: false },
  }
  let report = aggregate_suite(gates)
  assert_false(report.release_ready)
  @test.assert_eq(report.directions.length(), direction_count)
  let mut ready_count = 0
  for d in report.directions {
    if d.release_ready {
      ready_count = ready_count + 1
    } else {
      @test.assert_eq(d.name, "dst")
    }
  }
  @test.assert_eq(ready_count, direction_count - 1)
}

///|
/// 穷举：对每一个方向，单独将其置为「未绿」都应使整体不就绪。
/// 通过逐一翻转 10 个方向之一，确保聚合门禁对全部方向都生效（无遗漏接入）。
test "aggregate_suite fails if exactly one direction is not green" {
  let green = gates_of(true)
  let red = gates_of(false)
  // 用「翻转第 i 个方向」的构造覆盖全部 10 个方向。
  let make = fn(i : Int) -> SuiteGates {
    {
      parser_combinator: if i == 0 {
        red
      } else {
        green
      },
      regex_engine: if i == 1 {
        red
      } else {
        green
      },
      serialization: if i == 2 {
        red
      } else {
        green
      },
      build_tool: if i == 3 {
        red
      } else {
        green
      },
      logging: if i == 4 {
        red
      } else {
        green
      },
      codegen_infra: if i == 5 {
        red
      } else {
        green
      },
      dst: if i == 6 {
        red
      } else {
        green
      },
      lsp: if i == 7 {
        red
      } else {
        green
      },
      mini_compiler: if i == 8 {
        red
      } else {
        green
      },
      actor: if i == 9 {
        red
      } else {
        green
      },
    }
  }
  for i in 0..<direction_count {
    let report = aggregate_suite(make(i))
    assert_false(report.release_ready)
    @test.assert_eq(report.directions.length(), direction_count)
  }
}

///|
/// 清单完整性：release_manifest 恰好枚举全部 10 个方向的发布身份，
/// 名称集合与预期一致（含以 "lsp" 标识的方向五），且无重复。
test "release_manifest enumerates all ten directions by name" {
  let manifest = release_manifest()
  @test.assert_eq(manifest.length(), direction_count)
  let expected = [
    "parser_combinator", "regex_engine", "serialization", "build_tool", "logging",
    "codegen_infra", "dst", "lsp", "mini_compiler", "actor",
  ]
  let names = manifest.map(fn(d) { d.name })
  for name in expected {
    assert_true(names.contains(name))
  }
  // 无重复：每个名称在清单中恰好出现一次。
  for name in expected {
    let mut occurrences = 0
    for n in names {
      if n == name {
        occurrences = occurrences + 1
      }
    }
    @test.assert_eq(occurrences, 1)
  }
}

///|
/// collect_direction_releases 与 release_manifest 顺序一致（按名称对齐），
/// 且各方向版本号为合法 SemVer。
test "collect_direction_releases aligns with manifest order and valid semver" {
  let releases = collect_direction_releases(uniform_suite_gates(gates_of(true)))
  let manifest = release_manifest()
  @test.assert_eq(releases.length(), manifest.length())
  for i in 0..<releases.length() {
    @test.assert_eq(releases[i].name, manifest[i].name)
    assert_true(@release_meta.is_valid_semver(releases[i].version))
  }
}

///|
/// 边界保护：空方向清单视为未就绪，防止「零方向」被误判为整体就绪。
test "suite_release_ready treats empty manifest as not ready" {
  let empty : Array[@release_meta.DirectionRelease] = []
  assert_false(suite_release_ready(empty))
}
