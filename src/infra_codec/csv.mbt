// csv.mbt —— CSV 编解码（RFC 4180）。
//
// 语义：
// - 字段含逗号 / 双引号 / 换行时必须加引号；引号内的 `"` 以 `""` 转义
//   （RFC 4180 §2 规则 5-7）；
// - 解析接受 LF 与 CRLF 两种行终止；末尾可选换行；
// - 引号字段后出现非分隔符、未闭合引号等畸形输入返回 None（总体函数）。

///|
/// 单字段是否需要加引号。
fn csv_needs_quote(field : String) -> Bool {
  for c in field.iter() {
    if c == ',' || c == '"' || c == '\n' || c == '\r' {
      return true
    }
  }
  false
}

///|
/// 编码一行（自动按需加引号与转义）。
pub fn csv_encode_row(fields : Array[String]) -> String {
  let sb = StringBuilder::new()
  for i, f in fields {
    if i > 0 {
      sb.write_char(',')
    }
    if csv_needs_quote(f) {
      sb.write_char('"')
      for c in f.iter() {
        if c == '"' {
          sb.write_string("\"\"")
        } else {
          sb.write_char(c)
        }
      }
      sb.write_char('"')
    } else {
      sb.write_string(f)
    }
  }
  sb.to_string()
}

///|
/// 编码多行（LF 行终止，末尾带换行）。
pub fn csv_encode(rows : Array[Array[String]]) -> String {
  let sb = StringBuilder::new()
  for row in rows {
    sb.write_string(csv_encode_row(row))
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// 解析 CSV 文本；畸形（未闭合引号、引号后杂字符）返回 None。
/// 空输入返回空表；末尾换行可选；接受 LF 与 CRLF。
pub fn csv_decode(text : String) -> Array[Array[String]]? {
  let chars = text.iter().to_array()
  let n = chars.length()
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let field = StringBuilder::new()
  let mut i = 0
  let mut in_field = false // 当前行是否已有内容（区分空行与空字段）
  while i < n {
    let c = chars[i]
    if c == '"' {
      // 引号字段：必须出现在字段开头。
      if field.is_empty() == false {
        return None
      }
      i = i + 1
      let mut closed = false
      while i < n {
        let q = chars[i]
        if q == '"' {
          if i + 1 < n && chars[i + 1] == '"' {
            field.write_char('"')
            i = i + 2
          } else {
            closed = true
            i = i + 1
            break
          }
        } else {
          field.write_char(q)
          i = i + 1
        }
      }
      if !closed {
        return None
      }
      // 引号闭合后只允许分隔符 / 行终止 / 文本结束。
      if i < n && chars[i] != ',' && chars[i] != '\n' && chars[i] != '\r' {
        return None
      }
      in_field = true
      continue
    }
    if c == ',' {
      row.push(field.to_string())
      field.reset()
      in_field = true
      i = i + 1
      continue
    }
    if c == '\r' {
      if i + 1 < n && chars[i + 1] == '\n' {
        i = i + 1
      }
      // 落到 '\n' 分支处理。
      row.push(field.to_string())
      field.reset()
      rows.push(row)
      row = []
      in_field = false
      i = i + 1
      continue
    }
    if c == '\n' {
      row.push(field.to_string())
      field.reset()
      rows.push(row)
      row = []
      in_field = false
      i = i + 1
      continue
    }
    field.write_char(c)
    in_field = true
    i = i + 1
  }
  // 末尾无换行的最后一行。
  if in_field || !field.is_empty() || row.length() > 0 {
    row.push(field.to_string())
    rows.push(row)
  }
  Some(rows)
}
