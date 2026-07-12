// examples/cli_devtool — runnable demonstration of the `src/infra_cli`
// direction as a deploy-tool CLI: declare a command with a subcommand,
// parse args with defaults and bundled shorts, validate typed values with
// choices, suggest fixes for typos, and emit help + bash completion.
//
// Run with:
//   moon run examples/cli_devtool

///|
fn deploy_command() -> @cli.Command {
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
fn main {
  let cmd = deploy_command()
  println("=== 1. parse a realistic invocation ===")
  let argv = [
    "deploy", "--service", "router", "-n", "4", "--env", "prod", "--dry-run",
  ]
  match @cli.parse(cmd, argv) {
    Ok(parsed) => {
      println("command path : \{parsed.command_path.join(" ")}")
      let svc = parsed.value_of("service").unwrap_or("?")
      println("service      : \{svc}")
      match parsed.int_of("replicas") {
        Ok(n) => println("replicas     : \{n} (typed Int64)")
        Err(e) => println("replicas err : \{e}")
      }
      println("dry-run flag : \{parsed.has_flag("dry-run")}")
      let region = parsed.value_of("region").unwrap_or("us-east-1")
      println("region       : \{region} (default applies)")
      println("")
      println("=== 2. typed validation with choices ===")
      let errors = @cli.validate_rules(parsed, [
        @cli.rule("replicas", required=true, vtype=VInt),
        @cli.rule("env", required=true, choices=["staging", "prod"]),
      ])
      println("rule errors  : \{errors.length()} (all rules satisfied)")
    }
    Err(e) => println("parse error: \{e}")
  }
  println("")
  println("=== 3. helpful failure: unknown flag + typo suggestion ===")
  match @cli.parse(cmd, ["deploy", "--servcie", "router"]) {
    Ok(_) => println("unexpectedly parsed")
    Err(e) => {
      println("error        : \{e}")
      match @cli.suggest_option("servcie", ["service", "replicas", "env"]) {
        Some(s) => println("did you mean : --\{s}")
        None => println("no suggestion")
      }
    }
  }
  println("")
  println("=== 4. bundled short flags expand ===")
  let expanded = @cli.expand_bundled_shorts(["-vd"], [
    @cli.flag_spec("verbose", "v", ""),
    @cli.flag_spec("dry-run", "d", ""),
  ])
  println("-vd expands to: \{expanded.join(" ")}")
  println("")
  println("=== 5. generated help ===")
  println(@cli.help_text(cmd))
  println("=== 6. bash completion (first lines) ===")
  let script = @cli.completion_bash(cmd)
  let lines = script.split("\n").collect()
  let upto = if lines.length() < 6 { lines.length() } else { 6 }
  for i in 0..<upto {
    println(lines[i].to_owned())
  }
  println("... (\{lines.length()} lines total)")
}
