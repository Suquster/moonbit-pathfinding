// cli_typed_test.mbt —— 类型化取值 / 声明式校验 / 组合短 flag 测试。

///|
fn mk_cmd() -> Command {
  {
    name: "app",
    about: "test app",
    specs: [
      flag_spec("verbose", "v", "verbose"),
      flag_spec("all", "a", "all"),
      flag_spec("force", "f", "force"),
      value_spec("count", "c", "count", None),
      value_spec("ratio", "r", "ratio", None),
      value_spec("mode", "m", "mode", None),
      value_spec("enabled", "e", "enabled", None),
    ],
    subcommands: [],
  }
}

///|
/// int_of / bool_of / float_of 正常与畸形路径。
test "typed accessors" {
  match
    parse(mk_cmd(), [
      "--count", "42", "--ratio", "-3.25", "--enabled", "YES", "--mode", "fast",
    ]) {
    Ok(p) => {
      assert_true(p.int_of("count") == Ok(42L))
      assert_true(p.float_of("ratio") == Ok(-3.25))
      assert_true(p.bool_of("enabled") == Ok(true))
      assert_true(p.int_of("mode") == Err(BadInt("mode", "fast")))
      assert_true(p.int_of("missing") == Err(NotPresent("missing")))
    }
    Err(_) => fail("expected parse ok")
  }
  match parse(mk_cmd(), ["--count", "+7", "--ratio", "10"]) {
    Ok(p) => {
      assert_true(p.int_of("count") == Ok(7L))
      assert_true(p.float_of("ratio") == Ok(10.0))
    }
    Err(_) => fail("expected parse ok")
  }
  match parse(mk_cmd(), ["--ratio", "1.2.3", "--enabled", "maybe"]) {
    Ok(p) => {
      assert_true(p.float_of("ratio") == Err(BadFloat("ratio", "1.2.3")))
      assert_true(p.bool_of("enabled") == Err(BadBool("enabled", "maybe")))
    }
    Err(_) => fail("expected parse ok")
  }
}

///|
/// 声明式校验：required / 类型 / choices 全部违例一次汇总（不短路）。
test "validate_rules aggregates all violations" {
  match parse(mk_cmd(), ["--count", "abc", "--mode", "warp"]) {
    Ok(p) => {
      let errs = validate_rules(p, [
        rule("count", vtype=VInt),
        rule("mode", choices=["fast", "slow"]),
        rule("ratio", required=true, vtype=VFloat),
      ])
      assert_true(errs.length() == 3)
      assert_true(errs[0] == BadInt("count", "abc"))
      assert_true(errs[1] == NotInChoices("mode", "warp"))
      assert_true(errs[2] == NotPresent("ratio"))
    }
    Err(_) => fail("expected parse ok")
  }
  // 全部合法 → 零违例。
  match parse(mk_cmd(), ["--count", "1", "--mode", "fast", "--ratio", "0.5"]) {
    Ok(p) => {
      let errs = validate_rules(p, [
        rule("count", vtype=VInt),
        rule("mode", choices=["fast", "slow"]),
        rule("ratio", required=true, vtype=VFloat),
      ])
      assert_true(errs.length() == 0)
    }
    Err(_) => fail("expected parse ok")
  }
}

///|
/// 组合短 flag：-vaf ≡ -v -a -f；含非 flag 成员则原样保留；-- 后不展开。
test "expand_bundled_shorts posix guideline 5" {
  let specs = mk_cmd().specs
  assert_true(
    expand_bundled_shorts(["-vaf", "x"], specs) == ["-v", "-a", "-f", "x"],
  )
  // c 是 Value 不是 Flag → 不展开。
  assert_true(expand_bundled_shorts(["-vc"], specs) == ["-vc"])
  // -- 之后原样。
  assert_true(expand_bundled_shorts(["--", "-vaf"], specs) == ["--", "-vaf"])
  // 与既有 parse 组合端到端。
  match parse(mk_cmd(), expand_bundled_shorts(["-vaf", "pos"], specs)) {
    Ok(p) => {
      assert_true(
        p.has_flag("verbose") && p.has_flag("all") && p.has_flag("force"),
      )
      assert_true(p.positionals == ["pos"])
    }
    Err(_) => fail("expected parse ok")
  }
}

///|
/// value_or_env：命令行 → 环境变量 → 默认值分层回退。
test "value_or_env layered fallback" {
  let parsed : ParsedArgs = {
    command_path: [],
    flags: [],
    values: [("output", "cli.txt")],
    positionals: [],
  }
  let env = [("APP_OUTPUT", "env.txt"), ("APP_LEVEL", "debug")]
  assert_true(
    parsed.value_or_env("output", "APP_OUTPUT", env) == Some("cli.txt"),
  )
  assert_true(parsed.value_or_env("level", "APP_LEVEL", env) == Some("debug"))
  assert_true(
    parsed.value_or_env("mode", "APP_MODE", env, default=Some("fast")) ==
    Some("fast"),
  )
  assert_true(parsed.value_or_env("mode", "APP_MODE", env) is None)
}

///|
/// flag_tristate：`--name` / `--no-name` / 缺省 三态。
test "flag tristate negation prefix" {
  let on : ParsedArgs = {
    command_path: [],
    flags: ["color"],
    values: [],
    positionals: [],
  }
  let off : ParsedArgs = {
    command_path: [],
    flags: ["no-color"],
    values: [],
    positionals: [],
  }
  let unset : ParsedArgs = {
    command_path: [],
    flags: [],
    values: [],
    positionals: [],
  }
  assert_true(on.flag_tristate("color") == Some(true))
  assert_true(off.flag_tristate("color") == Some(false))
  assert_true(unset.flag_tristate("color") is None)
}

///|
/// Damerau–Levenshtein：含相邻换位的距离。
test "dl distance with transposition" {
  assert_true(dl_distance("", "abc") == 3)
  assert_true(dl_distance("abc", "abc") == 0)
  assert_true(dl_distance("ca", "ac") == 1) // 换位
  assert_true(dl_distance("verbose", "verbos") == 1)
  assert_true(dl_distance("kitten", "sitting") == 3)
}

///|
/// did-you-mean：距离 ≤2 才建议、并列取字典序最小。
test "suggest option did you mean" {
  let cands = ["verbose", "version", "output", "color"]
  assert_true(suggest_option("verbos", cands) == Some("verbose"))
  assert_true(suggest_option("versio", cands) == Some("version"))
  assert_true(suggest_option("zzzzzz", cands) is None)
  assert_true(suggest_option("outpot", cands) == Some("output"))
}
