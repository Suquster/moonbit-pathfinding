// infra_cli_bench.mbt —— CLI 方向基准：解析 / 校验 / 拼写建议 /
// help 生成在真实形状的命令定义上的吞吐对比。

///|
fn cb_command() -> @cli.Command {
  {
    name: "shipit",
    about: "deploy services to a cluster",
    specs: [
      @cli.flag_spec("verbose", "v", "enable verbose logging"),
      @cli.value_spec("region", "r", "target region", Some("us-east-1")),
    ],
    subcommands: [
      {
        name: "deploy",
        about: "roll out a service version",
        specs: [
          @cli.value_spec("service", "s", "service name", None),
          @cli.value_spec("replicas", "n", "replica count", Some("2")),
          @cli.value_spec("env", "e", "target environment", Some("staging")),
          @cli.flag_spec("dry-run", "d", "plan only, no changes"),
        ],
        subcommands: [],
      },
    ],
  }
}

///|
test "smoke: parse + validate + suggestion behave as documented" {
  let cmd = cb_command()
  let argv = [
    "deploy", "--service", "router", "-n", "4", "--env", "prod", "--dry-run",
  ]
  match @cli.parse(cmd, argv) {
    Ok(parsed) => {
      assert_true(parsed.value_of("service") is Some("router"))
      assert_true(parsed.has_flag("dry-run"))
      let errors = @cli.validate_rules(parsed, [
        @cli.rule("replicas", required=true, vtype=VInt),
        @cli.rule("env", required=true, choices=["staging", "prod"]),
      ])
      assert_eq(errors.length(), 0)
    }
    Err(_) => assert_true(false)
  }
  assert_true(
    @cli.suggest_option("servcie", ["service", "replicas", "env"])
    is Some("service"),
  )
}

///|
test "bench: parse / validate / suggest / help throughput" (b : @bench.T) {
  let cmd = cb_command()
  let argv = [
    "deploy", "--service", "router", "-n", "4", "--env", "prod", "--dry-run",
  ]
  b.bench(name="parse_512", fn() {
    let mut ok = 0
    for _ in 0..<512 {
      match @cli.parse(cmd, argv) {
        Ok(_) => ok = ok + 1
        Err(_) => ()
      }
    }
    b.keep(ok)
  })
  let parsed = match @cli.parse(cmd, argv) {
    Ok(p) => p
    Err(_) => abort("parse failed")
  }
  let rules = [
    @cli.rule("replicas", required=true, vtype=@cli.ValueType::VInt),
    @cli.rule("env", required=true, choices=["staging", "prod"]),
  ]
  b.bench(name="validate_rules_512", fn() {
    let mut errs = 0
    for _ in 0..<512 {
      errs = errs + @cli.validate_rules(parsed, rules).length()
    }
    b.keep(errs)
  })
  let options = [
    "service", "replicas", "env", "region", "verbose", "dry-run", "timeout", "retries",
  ]
  b.bench(name="suggest_option_512", fn() {
    let mut hits = 0
    for _ in 0..<512 {
      match @cli.suggest_option("servcie", options) {
        Some(_) => hits = hits + 1
        None => ()
      }
    }
    b.keep(hits)
  })
  b.bench(name="help_text_512", fn() {
    let mut total = 0
    for _ in 0..<512 {
      total = total + @cli.help_text(cmd).length()
    }
    b.keep(total)
  })
}
