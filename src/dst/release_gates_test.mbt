// release_gates_test.mbt —— 发布门禁真值表测试（任务 19.6）。
//
// 覆盖 release_info_with_gates：三后端测试 / 证明谓词 / 可执行文档任一未过即阻止本
// 方向进入 release-ready（R13.1 / R13.2 / R13.6）。

///|
/// 门禁真值表：三项全过才就绪，任一未过即阻止 release-ready。
test "release gates block release-ready unless all gates pass" {
  let all_pass : @release_meta.QualityGates = {
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  }
  assert_true(release_info_with_gates(all_pass).release_ready)
  let no_tests : @release_meta.QualityGates = {
    tests_passing: false,
    proofs_passing: true,
    docs_passing: true,
  }
  assert_false(release_info_with_gates(no_tests).release_ready)
  let no_proofs : @release_meta.QualityGates = {
    tests_passing: true,
    proofs_passing: false,
    docs_passing: true,
  }
  assert_false(release_info_with_gates(no_proofs).release_ready)
  let no_docs : @release_meta.QualityGates = {
    tests_passing: true,
    proofs_passing: true,
    docs_passing: false,
  }
  assert_false(release_info_with_gates(no_docs).release_ready)
}

///|
/// 门禁评估不改变方向身份字段（name / version）。
test "release gates preserve direction identity" {
  let ready = release_info_with_gates({
    tests_passing: true,
    proofs_passing: true,
    docs_passing: true,
  })
  assert_eq(ready.name, "dst")
  assert_eq(ready.version, dst_version)
}
