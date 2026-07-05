// error_report.mbt —— L0 错误报告渲染（error report rendering）。
//
// 对标 megaparsec 的 `ParseErrorBundle` / `errorBundlePretty`：把 `Fail(pos,
// expected~)` 与源输入结合，渲染为带源码行摘录与插入符（caret）定位的
// 多行人类可读诊断（Requirement 6 / roadmap T4.2）。
//
// 渲染格式（与 megaparsec 同构）：
//
//   ```
//   3:5:
//     |
//   3 | let x = @ 1
//     |         ^
//   unexpected '@'
//   expecting 数字, '('
//   ```
//
// 设计要点：
//   * 位置信息直接取自 `Pos`（最远失败合并后的 line/col，见 error_model.mbt）；
//   * 源码行摘录按 `pos.line` 从源输入中切出（按 '\n' 分行，不含行终止符）；
//   * caret 列按 `pos.col` 对齐（1 起始）；
//   * `unexpected` 取失败位置处的实际字符（EOF 时为「输入末尾」）；
//   * `expecting` 列出去重后的期望符号集合（顺序与 `expected` 一致）。

///|
/// 内部辅助：从源输入中切出第 `line`（1 起始）行的内容（不含 '\n'）。
/// 行号越界时返回空串。
fn source_line_at(source : String, line : Int) -> String {
  let sb = StringBuilder::new()
  let mut cur_line = 1
  for c in source {
    if c == '\n' {
      if cur_line == line {
        break
      }
      cur_line = cur_line + 1
    } else if cur_line == line {
      sb.write_char(c)
    }
  }
  if cur_line < line {
    ""
  } else {
    sb.to_string()
  }
}

///|
/// 内部辅助：描述失败位置处的实际输入（unexpected item）。
/// 位置在输入内时为该字符的带引号形式；已到末尾时为「输入末尾」。
fn unexpected_at(source : String, pos : Pos) -> String {
  match source.get_char(pos.offset) {
    Some('\n') => "换行"
    Some(c) => "'\{c}'"
    None => "输入末尾"
  }
}

///|
/// 把解析失败渲染为带源码行摘录与 caret 定位的多行诊断（对标 megaparsec
/// `errorBundlePretty`）。成功结果返回 `None`。
///
/// 输出各行依次为：`行:列:` 头、对齐竖线、`行号 | 源码行`、caret 行、
/// `unexpected 实际字符`、`expecting 期望集合`（期望为空时省略该行）。
pub fn[T] render_error(result : ParseResult[T], source : String) -> String? {
  match result {
    Ok(_, _) => None
    Fail(pos, expected~) => {
      let line_text = source_line_at(source, pos.line)
      let line_no = "\{pos.line}"
      // 竖线列与行号宽度对齐（megaparsec 同款排版）。
      let pad = StringBuilder::new()
      for _i in 0..<line_no.length() {
        pad.write_char(' ')
      }
      let gutter = pad.to_string()
      let caret = StringBuilder::new()
      for _i in 1..<pos.col {
        caret.write_char(' ')
      }
      caret.write_char('^')
      let out = StringBuilder::new()
      out.write_string("\{pos.line}:\{pos.col}:\n")
      out.write_string("\{gutter} |\n")
      out.write_string("\{line_no} | \{line_text}\n")
      out.write_string("\{gutter} | \{caret.to_string()}\n")
      out.write_string("unexpected \{unexpected_at(source, pos)}")
      let uniq = normalize_expected(expected)
      if uniq.length() > 0 {
        out.write_string("\nexpecting ")
        for i, e in uniq {
          if i > 0 {
            out.write_string(", ")
          }
          out.write_string(e)
        }
      }
      Some(out.to_string())
    }
  }
}

///|
/// 便捷入口：在字符串上运行解析器，失败时直接产出渲染后的诊断。
pub fn[T] Parser::explain_failure(self : Parser[T], source : String) -> String? {
  render_error(self.parse_string(source), source)
}
