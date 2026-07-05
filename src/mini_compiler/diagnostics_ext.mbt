// diagnostics_ext.mbt —— T1.4 诊断增强：类型错误的源位置渲染 + 修复建议
// （对标 Elm / Rust 风格错误报告；旁路新增，不改任何既有签名）。
//
// 输入为既有 `Diagnostic`（kind/line/col/msg，行列 1 起始）与源文本，输出
// 多行报告：
//   1. 标题行 `type error @ line:col — <msg>`；
//   2. 源码行摘录 + caret（^）指示列位置（与 parser_combinator 的
//      render_error 同风格）；
//   3. 按消息形态匹配的修复建议（hint）。
//
// 修复建议规则（模式匹配 `unify` / `infer` 的确定性消息文法）：
//   * `cannot unify TyInt with TyBool`（或反向）—— 分支/条件处类型不一致；
//   * `cannot unify ... TyFun ...` 与非函数 —— 把非函数值当函数调用；
//   * 元组 ~ 元组 —— 元数或分量类型不一致；
//   * `occurs check` —— 无限类型（常见于自应用）；
//   * `未绑定变量` —— 拼写或作用域问题。

///|
/// 渲染 caret 前导空白的填充字符。
let caret_pad_char : Char = ' '

///|
/// 提取源文本第 `line`（1 起始）行；越界返回空串。
fn source_line_at(src : String, line : Int) -> String {
  let mut cur = 1
  let sb = @infra_text.TextBuilder::new()
  for c in src {
    if c == '\n' {
      if cur == line {
        return sb.build()
      }
      cur = cur + 1
    } else if cur == line {
      sb.push_char(c)
    }
  }
  if cur == line {
    sb.build()
  } else {
    ""
  }
}

///|
/// 按诊断消息形态给出修复建议；无匹配规则返回 None。
fn suggestion_for(msg : String) -> String? {
  if msg.contains("occurs check") {
    return Some(
      "无限类型通常来自把函数应用于自身或循环的数据流；检查该表达式是否把一个值同时当作函数与其参数使用",
    )
  }
  if msg.contains("未绑定变量") {
    return Some(
      "检查变量名拼写，或确认它是否在当前作用域（let/fun/let rec）中先被绑定",
    )
  }
  if msg.contains("cannot unify") {
    let has_int = msg.contains("TyInt")
    let has_bool = msg.contains("TyBool")
    let has_fun = msg.contains("TyFun")
    let has_tuple = msg.contains("TyTuple")
    if has_fun && (has_int || has_bool) {
      return Some(
        "似乎把一个非函数值当函数调用（或把函数用于算术/比较）；检查调用处的括号与参数个数",
      )
    }
    if has_tuple {
      return Some(
        "元组的元数或分量类型不一致；检查解构与构造处的分量个数与各分量类型",
      )
    }
    if has_int && has_bool {
      return Some(
        "整数与布尔混用：if 条件需要 Bool（用比较运算获得），算术操作数需要 Int；检查两分支/操作数的类型是否一致",
      )
    }
    return Some(
      "两侧类型不一致；从标注的位置向内检查子表达式的期望类型与实际类型",
    )
  }
  None
}

///|
/// 渲染类型错误的完整多行报告（T1.4）：标题 + 源码行摘录 + caret + 修复建议。
/// 非 TypeError 诊断同样可渲染（标题按 kind 文本化）。
pub fn render_diagnostic(src : String, d : Diagnostic) -> String {
  let sb = @infra_text.TextBuilder::new()
  // 标题行。
  sb.push_str("type error @ ")
  sb.push_str(d.line.to_string())
  sb.push_char(':')
  sb.push_str(d.col.to_string())
  sb.push_str(" — ")
  sb.push_str(d.msg)
  sb.push_char('\n')
  // 源码行摘录 + caret（行列合法时）。
  let line_text = source_line_at(src, d.line)
  if d.line >= 1 && d.col >= 1 && line_text.length() > 0 {
    sb.push_str("  | ")
    sb.push_str(line_text)
    sb.push_char('\n')
    sb.push_str("  | ")
    let mut k = 1
    while k < d.col {
      sb.push_char(caret_pad_char)
      k = k + 1
    }
    sb.push_char('^')
    sb.push_char('\n')
  }
  // 修复建议。
  match suggestion_for(d.msg) {
    Some(hint) => {
      sb.push_str("  hint: ")
      sb.push_str(hint)
      sb.push_char('\n')
    }
    None => ()
  }
  sb.build()
}
