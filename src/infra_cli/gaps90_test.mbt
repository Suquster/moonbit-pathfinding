// gaps90_test.mbt —— 类型化校验/建议余臂（第九十批）。

///|
/// validate_rules：VBool 规则畸形值上报。
test "validate_rules：VBool 规则畸形值上报" {
  let p : ParsedArgs = {
    command_path: [],
    flags: [],
    values: [("verbose", "maybe")],
    positionals: [],
  }
  let errs = validate_rules(p, [rule("verbose", vtype=VBool, required=true)])
  assert_eq(errs.length(), 1)
}

///|
/// suggest_option：等距候选取字典序较小者。
test "suggest_option：等距候选字典序决胜" {
  assert_eq(suggest_option("ab", ["ay", "ax"]), Some("ax"))
}
