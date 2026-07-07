// cli_test.mbt —— CLI 解析测试：POSIX/GNU 语义 + 子命令 + 错误路径 + PBT。

///|
fn demo_cmd() -> @infra_cli.Command {
  {
    name: "pathfind",
    about: "shortest path toolkit",
    specs: [
      @infra_cli.flag_spec("verbose", "v", "enable verbose output"),
      @infra_cli.value_spec("output", "o", "output file", Some("out.txt")),
      @infra_cli.value_spec("threads", "", "worker threads", None),
    ],
    subcommands: [
      {
        name: "bench",
        about: "run benchmarks",
        specs: [
          @infra_cli.flag_spec("quick", "q", "quick mode"),
          @infra_cli.value_spec("iters", "n", "iterations", Some("10")),
        ],
        subcommands: [],
      },
    ],
  }
}

///|
test "parse long and short flags" {
  let r = @infra_cli.parse(demo_cmd(), ["--verbose", "input.txt"]).unwrap()
  assert_true(r.has_flag("verbose"))
  assert_true(r.positionals == ["input.txt"])
  let r2 = @infra_cli.parse(demo_cmd(), ["-v"]).unwrap()
  assert_true(r2.has_flag("verbose"))
  let r3 = @infra_cli.parse(demo_cmd(), []).unwrap()
  assert_true(!r3.has_flag("verbose"))
}

///|
test "parse value options in both forms" {
  // --name value 形式。
  let r = @infra_cli.parse(demo_cmd(), ["--output", "a.txt"]).unwrap()
  assert_true(r.value_of("output") == Some("a.txt"))
  // --name=value 形式。
  let r2 = @infra_cli.parse(demo_cmd(), ["--output=b.txt"]).unwrap()
  assert_true(r2.value_of("output") == Some("b.txt"))
  // 短名取值。
  let r3 = @infra_cli.parse(demo_cmd(), ["-o", "c.txt"]).unwrap()
  assert_true(r3.value_of("output") == Some("c.txt"))
  // 值内含 '='（split 只按第一个 '=' 分割）。
  let r4 = @infra_cli.parse(demo_cmd(), ["--output=k=v"]).unwrap()
  assert_true(r4.value_of("output") == Some("k=v"))
}

///|
test "default values fill unset options" {
  let r = @infra_cli.parse(demo_cmd(), []).unwrap()
  assert_true(r.value_of("output") == Some("out.txt"))
  // 无默认值且未提供 → None。
  assert_true(r.value_of("threads") == None)
  // 显式提供覆盖默认。
  let r2 = @infra_cli.parse(demo_cmd(), ["--output", "x"]).unwrap()
  assert_true(r2.value_of("output") == Some("x"))
}

///|
test "double dash terminates option parsing" {
  let r = @infra_cli.parse(demo_cmd(), ["--", "--verbose", "-o"]).unwrap()
  assert_true(!r.has_flag("verbose"))
  assert_true(r.positionals == ["--verbose", "-o"])
}

///|
test "subcommand dispatch" {
  let r = @infra_cli.parse(demo_cmd(), ["bench", "--quick", "--iters=100"]).unwrap()
  assert_true(r.command_path == ["bench"])
  assert_true(r.has_flag("quick"))
  assert_true(r.value_of("iters") == Some("100"))
  // 子命令默认值。
  let r2 = @infra_cli.parse(demo_cmd(), ["bench"]).unwrap()
  assert_true(r2.value_of("iters") == Some("10"))
  // 位置参数出现后不再匹配子命令。
  let r3 = @infra_cli.parse(demo_cmd(), ["file.txt", "bench"]).unwrap()
  assert_true(r3.command_path == [])
  assert_true(r3.positionals == ["file.txt", "bench"])
}

///|
test "error paths are structured" {
  assert_true(
    @infra_cli.parse(demo_cmd(), ["--nope"]) ==
    Err(@infra_cli.CliError::UnknownFlag("--nope")),
  )
  assert_true(
    @infra_cli.parse(demo_cmd(), ["--output"]) ==
    Err(@infra_cli.CliError::MissingValue("output")),
  )
  // flag 不接受 = 值。
  assert_true(
    @infra_cli.parse(demo_cmd(), ["--verbose=yes"]) ==
    Err(@infra_cli.CliError::MissingValue("verbose")),
  )
  // 重复规格定义。
  let bad : @infra_cli.Command = {
    name: "bad",
    about: "",
    specs: [
      @infra_cli.flag_spec("x", "", ""),
      @infra_cli.flag_spec("x", "", ""),
    ],
    subcommands: [],
  }
  assert_true(
    @infra_cli.parse(bad, []) == Err(@infra_cli.CliError::DuplicateSpec("x")),
  )
}

///|
test "help text renders usage options and subcommands" {
  let h = @infra_cli.help_text(demo_cmd())
  assert_true(h.contains("USAGE:"))
  assert_true(h.contains("--verbose"))
  assert_true(h.contains("-v, "))
  assert_true(h.contains("--output <VALUE>"))
  assert_true(h.contains("[default: out.txt]"))
  assert_true(h.contains("SUBCOMMANDS:"))
  assert_true(h.contains("bench"))
}

///|
test "parser never crashes on random tokens (pbt)" {
  let rng = @infra_pbt.rng_new(20260707UL)
  let pool = [
    "--verbose", "-v", "--output", "-o", "x.txt", "--", "bench", "--iters=3", "-q",
    "--nope", "=", "-", "--output=", "a=b",
  ]
  for _ in 0..<200 {
    let argv : Array[String] = []
    for _ in 0..<rng.next_below(8) {
      argv.push(pool[rng.next_below(pool.length())])
    }
    // 总体性：要么 Ok 要么结构化 Err，绝不 abort。
    match @infra_cli.parse(demo_cmd(), argv) {
      Ok(r) => assert_true(r.positionals.length() <= argv.length())
      Err(e) =>
        assert_true(
          e is @infra_cli.CliError::UnknownFlag(_) ||
          e is @infra_cli.CliError::MissingValue(_) ||
          e is @infra_cli.CliError::DuplicateSpec(_),
        )
    }
  }
}
