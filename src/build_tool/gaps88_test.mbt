// gaps88_test.mbt —— include 合并/嵌套错误传播余臂（第八十八批）。

///|
/// include 子文件的变量并入父集，父定义优先（重名不覆盖）。
test "parse_rules_full_with_includes：变量合并且父定义优先" {
  let resolve = fn(path : String) -> String? {
    if path == "vars.mk" {
      Some("CC = clang\nEXTRA = -O2\nutil.o: util.c\n")
    } else {
      None
    }
  }
  match
    @build_tool.parse_rules_full_with_includes(
      "CC = gcc\ninclude vars.mk\napp: util.o\n", resolve,
    ) {
    Ok(rs) => {
      assert_eq(rs.variables.get("CC"), Some("gcc"))
      assert_eq(rs.variables.get("EXTRA"), Some("-O2"))
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}

///|
/// 嵌套 include 内层不可解析时，错误向外层传播。
test "parse_rules_full_with_includes：嵌套 include 错误传播" {
  let resolve = fn(path : String) -> String? {
    if path == "outer.mk" {
      Some("include missing.mk\n")
    } else {
      None
    }
  }
  assert_true(
    @build_tool.parse_rules_full_with_includes(
      "include outer.mk\napp: util.o\n", resolve,
    )
    is Err(_),
  )
}
