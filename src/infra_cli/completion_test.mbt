// shell 补全脚本生成测试（bash source 实测 + 结构断言）。

///|
/// 测试命令树（git 风格：全局选项 + 两个子命令）。
fn comp_demo_cmd() -> Command {
  {
    name: "mytool",
    about: "demo tool",
    specs: [
      flag_spec("verbose", "v", "enable verbose output"),
      value_spec("config", "c", "config file path", None),
    ],
    subcommands: [
      {
        name: "build",
        about: "build the project",
        specs: [
          flag_spec("release", "r", "release mode"),
          value_spec("jobs", "j", "parallel jobs", Some("4")),
        ],
        subcommands: [],
      },
      {
        name: "clean",
        about: "remove artifacts",
        specs: [flag_spec("dry-run", "", "print only [safe]")],
        subcommands: [],
      },
    ],
  }
}

///|
/// bash 脚本结构：complete 注册、compgen 词表、子命令 case 分派。
test "bash completion structure" {
  let script = completion_bash(comp_demo_cmd())
  assert_true(script.contains("complete -F _mytool mytool"))
  assert_true(script.contains("--verbose"))
  assert_true(script.contains("-v"))
  assert_true(script.contains("--config"))
  assert_true(script.contains("build"))
  assert_true(script.contains("clean"))
  // 子命令分支包含子命令自己的选项。
  assert_true(script.contains("--release"))
  assert_true(script.contains("--jobs"))
  assert_true(script.contains("compgen -W"))
  assert_true(script.contains("COMP_WORDS"))
}

///|
/// zsh 脚本结构：#compdef 头、_arguments、_describe 子命令、状态机。
test "zsh completion structure" {
  let script = completion_zsh(comp_demo_cmd())
  assert_true(script.contains("#compdef mytool"))
  assert_true(script.contains("_arguments -C"))
  assert_true(script.contains("_describe -t commands"))
  assert_true(script.contains("'build:build the project'"))
  assert_true(script.contains("'clean:remove artifacts'"))
  // 长短名互斥组：(-v --verbose)。
  assert_true(script.contains("(-v --verbose)"))
  // Value 类型带值占位。
  assert_true(script.contains(":value:"))
  // help 中的方括号被转义。
  assert_true(script.contains("\\[safe\\]"))
}

///|
/// 无子命令的扁平命令也能生成两种脚本。
test "completion for flat command" {
  let flat : Command = {
    name: "flat",
    about: "no subcommands",
    specs: [flag_spec("force", "f", "force")],
    subcommands: [],
  }
  let bash = completion_bash(flat)
  assert_true(bash.contains("complete -F _flat flat"))
  assert_true(bash.contains("--force"))
  let zsh = completion_zsh(flat)
  assert_true(zsh.contains("#compdef flat"))
  assert_true(zsh.contains("(-f --force)"))
}
