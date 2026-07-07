// completion.mbt —— shell 补全脚本生成（clap_complete / cobra 同款能力）。
//
// paper-to-code：
// - bash：programmable completion（bash 手册 §8.6/8.7）——`complete -F`
//   注册补全函数，函数按 `COMP_WORDS`/`COMP_CWORD` 定位当前词，
//   用 `compgen -W "候选词表"` 过滤前缀；子命令走 case 分派
//   （git-completion.bash / cobra 生成器同构套路）；
// - zsh：zsh completion system（zshcompsys(1)）——`#compdef` 头 +
//   `_arguments` 描述选项（`--name[help]`）与位置参数，
//   子命令用 `_describe` + curcontext 状态机（clap_complete 生成器同构）。
//
// 纯函数生成器：`Command`（含子命令树）→ 可直接 source 的脚本文本。

///|
/// 命令的候选词表：全部长/短选项 + 子命令名（bash compgen -W 用）。
fn word_list(cmd : Command) -> String {
  let sb = StringBuilder::new()
  let mut first = true
  let push = fn(w : String) -> Unit {
    if !first {
      sb.write_char(' ')
    }
    sb.write_string(w)
    first = false
  }
  for s in cmd.specs {
    push("--" + s.name)
    if s.short != "" {
      push("-" + s.short)
    }
  }
  for sub in cmd.subcommands {
    push(sub.name)
  }
  sb.to_string()
}

///|
/// 生成 bash 补全脚本（`source` 即用；`complete -F _prog prog` 注册）。
/// 子命令按已输入词做 case 分派，选项与子命令名均参与 `compgen` 过滤。
pub fn completion_bash(cmd : Command) -> String {
  let sb = StringBuilder::new()
  let fname = "_" + cmd.name
  sb.write_string("# bash completion for " + cmd.name + " (generated)\n")
  sb.write_string(fname + "() {\n")
  sb.write_string("    local cur prev words cword\n")
  sb.write_string("    cur=\"${COMP_WORDS[COMP_CWORD]}\"\n")
  sb.write_string("    prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n")
  sb.write_string("    local subcmd=\"\"\n")
  sb.write_string("    local i\n")
  sb.write_string("    for ((i=1; i < COMP_CWORD; i++)); do\n")
  sb.write_string("        case \"${COMP_WORDS[i]}\" in\n")
  for sub in cmd.subcommands {
    sb.write_string(
      "            " + sub.name + ") subcmd=\"" + sub.name + "\"; break ;;\n",
    )
  }
  sb.write_string("        esac\n")
  sb.write_string("    done\n")
  sb.write_string("    case \"$subcmd\" in\n")
  for sub in cmd.subcommands {
    sb.write_string("        " + sub.name + ")\n")
    sb.write_string(
      "            COMPREPLY=($(compgen -W \"" +
      word_list(sub) +
      "\" -- \"$cur\"))\n",
    )
    sb.write_string("            return ;;\n")
  }
  sb.write_string("        *)\n")
  sb.write_string(
    "            COMPREPLY=($(compgen -W \"" +
    word_list(cmd) +
    "\" -- \"$cur\"))\n",
  )
  sb.write_string("            return ;;\n")
  sb.write_string("    esac\n")
  sb.write_string("}\n")
  sb.write_string("complete -F " + fname + " " + cmd.name + "\n")
  sb.to_string()
}

///|
/// zsh `_arguments` 单条选项描述：`--name[help]` / `(-s --name)'{-s,--name}'[help]`。
fn zsh_arg_line(s : ArgSpec) -> String {
  // help 里的方括号转义（zsh 语法字符）。
  let esc_sb = StringBuilder::new()
  for c in s.help {
    if c == '[' || c == ']' {
      esc_sb.write_char('\\')
    }
    esc_sb.write_char(c)
  }
  let esc = esc_sb.to_string()
  let value_suffix = match s.kind {
    Value => ":value:" // 需要参数值
    Flag => ""
  }
  if s.short != "" {
    "    '(-" +
    s.short +
    " --" +
    s.name +
    ")'{-" +
    s.short +
    ",--" +
    s.name +
    "}'[" +
    esc +
    "]" +
    value_suffix +
    "' \\\n"
  } else {
    "    '--" + s.name + "[" + esc + "]" + value_suffix + "' \\\n"
  }
}

///|
/// 生成 zsh 补全脚本（`#compdef` 头 + `_arguments` + 子命令状态机；
/// clap_complete zsh 生成器同构）。
pub fn completion_zsh(cmd : Command) -> String {
  let sb = StringBuilder::new()
  sb.write_string("#compdef " + cmd.name + "\n\n")
  // 子命令列表函数。
  if cmd.subcommands.length() > 0 {
    sb.write_string("_" + cmd.name + "_commands() {\n")
    sb.write_string("    local commands; commands=(\n")
    for sub in cmd.subcommands {
      sb.write_string("        '" + sub.name + ":" + sub.about + "'\n")
    }
    sb.write_string("    )\n")
    sb.write_string(
      "    _describe -t commands '" + cmd.name + " commands' commands\n",
    )
    sb.write_string("}\n\n")
  }
  sb.write_string("_" + cmd.name + "() {\n")
  sb.write_string("    local curcontext=\"$curcontext\" state line\n")
  sb.write_string("    _arguments -C \\\n")
  for s in cmd.specs {
    sb.write_string(zsh_arg_line(s))
  }
  if cmd.subcommands.length() > 0 {
    sb.write_string("    '1: :_" + cmd.name + "_commands' \\\n")
    sb.write_string("    '*::arg:->args'\n")
    sb.write_string("    case $state in\n")
    sb.write_string("    args)\n")
    sb.write_string("        case $line[1] in\n")
    for sub in cmd.subcommands {
      sb.write_string("        " + sub.name + ")\n")
      sb.write_string("            _arguments \\\n")
      for s in sub.specs {
        sb.write_string("    " + zsh_arg_line(s))
      }
      sb.write_string("                ;;\n")
    }
    sb.write_string("        esac\n")
    sb.write_string("        ;;\n")
    sb.write_string("    esac\n")
  } else {
    sb.write_string("    '*::arg:->args'\n")
  }
  sb.write_string("}\n\n")
  sb.write_string("_" + cmd.name + " \"$@\"\n")
  sb.to_string()
}
