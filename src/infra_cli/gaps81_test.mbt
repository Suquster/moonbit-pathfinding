// gaps81_test.mbt —— CliError 诊断渲染余臂（第八十一批）。

///|
/// DuplicateSpec 的 Show 渲染。
test "cli：DuplicateSpec 诊断渲染" {
  let e : CliError = DuplicateSpec("--verbose")
  assert_eq("\{e}", "duplicate spec: --verbose")
}
