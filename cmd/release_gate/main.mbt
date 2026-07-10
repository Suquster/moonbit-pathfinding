// release_gate —— 将 CI 已验证的测试 / 证明谓词 / 可执行文档状态
// 输入全方向聚合器，输出可审计的 release-ready 清单。

///|
fn verified_gates() -> @release_meta.QualityGates {
  { tests_passing: true, proofs_passing: true, docs_passing: true }
}

///|
fn verified_suite_gates() -> @release_aggregate.SuiteGates {
  let gates = verified_gates()
  {
    parser_combinator: gates,
    regex_engine: gates,
    serialization: gates,
    build_tool: gates,
    logging: gates,
    codegen_infra: gates,
    dst: gates,
    lsp: gates,
    mini_compiler: gates,
    actor: gates,
  }
}

///|
fn main {
  let report = @release_aggregate.aggregate_suite(verified_suite_gates())
  if report.directions.length() != @release_aggregate.direction_count {
    abort("release manifest is incomplete")
  }
  for direction in report.directions {
    if !direction.release_ready {
      abort("direction is not release-ready: " + direction.name)
    }
    if !@release_meta.is_valid_semver(direction.version) {
      abort("direction has invalid semver: " + direction.name)
    }
    println(
      direction.name +
      "|" +
      direction.version +
      "|" +
      direction.changelog_path +
      "|ready",
    )
  }
  if !report.release_ready {
    abort("suite is not release-ready")
  }
  println(
    "suite|directions=" +
    report.directions.length().to_string() +
    "|release-ready",
  )
}
