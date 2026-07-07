// unified.mbt —— unified diff 格式输出与解析/应用（infra_diff 补深）。
//
// paper-to-code：GNU diffutils unified format（`diff -u` / POSIX `patch`
// 输入格式）：
// - hunk 头 `@@ -l,s +l,s @@`（1 起算起始行 + 长度；长度 1 可省略、
//   空侧起始行为 0）；
// - 上下文合并：编辑点前后各 `context` 行 Keep，相邻编辑间隔 ≤ 2×context
//   合并为同一 hunk（与 GNU diff 语义一致）；
// - `parse_unified` / `apply_unified`：解析 hunk 并按上下文校验后应用
//   （上下文不匹配 → None，对标 `patch` 的 reject 行为）。
//
// 在既有 Myers `diff_lines` 之上旁路构建；全部纯函数。

///|
/// unified diff 的一个 hunk。
pub(all) struct Hunk {
  old_start : Int // 1 起算（空侧为 0）
  old_count : Int
  new_start : Int
  new_count : Int
  lines : Array[DiffOp]
} derive(Eq, Debug)

///|
/// 由编辑脚本切分 hunk（前后各 context 行上下文，间隔 ≤ 2×context 合并）。
pub fn hunks_of(ops : Array[DiffOp], context? : Int = 3) -> Array[Hunk] {
  // 标记需要保留的 Keep 下标：距任一编辑 ≤ context。
  let n = ops.length()
  let is_edit : Array[Bool] = Array::make(n, false)
  let mut any_edit = false
  for i in 0..<n {
    if !(ops[i] is Keep(_)) {
      is_edit[i] = true
      any_edit = true
    }
  }
  if !any_edit {
    return []
  }
  let keep : Array[Bool] = Array::make(n, false)
  for i in 0..<n {
    if is_edit[i] {
      let lo = if i - context < 0 { 0 } else { i - context }
      let hi = if i + context >= n { n - 1 } else { i + context }
      for j in lo..<=hi {
        keep[j] = true
      }
    }
  }
  // 扫描连续 keep 段落，累计新旧行号。
  let hunks : Array[Hunk] = []
  let mut old_ln = 1
  let mut new_ln = 1
  let mut i = 0
  while i < n {
    if !keep[i] {
      match ops[i] {
        Keep(_) => {
          old_ln = old_ln + 1
          new_ln = new_ln + 1
        }
        Delete(_) => old_ln = old_ln + 1
        Insert(_) => new_ln = new_ln + 1
      }
      i = i + 1
      continue
    }
    let start_old = old_ln
    let start_new = new_ln
    let lines : Array[DiffOp] = []
    let mut oc = 0
    let mut nc = 0
    while i < n && keep[i] {
      lines.push(ops[i])
      match ops[i] {
        Keep(_) => {
          oc = oc + 1
          nc = nc + 1
          old_ln = old_ln + 1
          new_ln = new_ln + 1
        }
        Delete(_) => {
          oc = oc + 1
          old_ln = old_ln + 1
        }
        Insert(_) => {
          nc = nc + 1
          new_ln = new_ln + 1
        }
      }
      i = i + 1
    }
    hunks.push({
      old_start: if oc == 0 {
        start_old - 1
      } else {
        start_old
      },
      old_count: oc,
      new_start: if nc == 0 {
        start_new - 1
      } else {
        start_new
      },
      new_count: nc,
      lines,
    })
  }
  hunks
}

///|
/// unified diff 文本（GNU `diff -u` 体格式；不含 ---/+++ 文件头，
/// 头由调用方按需拼接）。
pub fn format_unified(
  old : Array[String],
  new : Array[String],
  context? : Int = 3,
) -> String {
  let ops = diff_lines(old, new)
  let hunks = hunks_of(ops, context~)
  let sb = StringBuilder::new()
  for h in hunks {
    sb.write_string(
      "@@ -" +
      h.old_start.to_string() +
      "," +
      h.old_count.to_string() +
      " +" +
      h.new_start.to_string() +
      "," +
      h.new_count.to_string() +
      " @@\n",
    )
    for l in h.lines {
      match l {
        Keep(s) => sb.write_string(" " + s + "\n")
        Delete(s) => sb.write_string("-" + s + "\n")
        Insert(s) => sb.write_string("+" + s + "\n")
      }
    }
  }
  sb.to_string()
}

///|
/// 解析 hunk 头 `@@ -l[,s] +l[,s] @@`；畸形返回 None。
fn parse_hunk_header(line : String) -> (Int, Int, Int, Int)? {
  if !line.has_prefix("@@ -") {
    return None
  }
  // 提取 "-l[,s] +l[,s]" 区段。
  let mut i = 4
  let read_num = fn(start : Int) -> (Int, Int)? {
    let mut j = start
    let mut acc = 0
    let mut seen = false
    while j < line.length() {
      let c = line.get_char(j).unwrap()
      if c >= '0' && c <= '9' {
        acc = acc * 10 + (c.to_int() - 48)
        seen = true
        j = j + 1
      } else {
        break
      }
    }
    if seen {
      Some((acc, j))
    } else {
      None
    }
  }
  guard read_num(i) is Some((old_start, j1)) else { return None }
  i = j1
  let mut old_count = 1
  if i < line.length() && line.get_char(i).unwrap() == ',' {
    guard read_num(i + 1) is Some((c, j2)) else { return None }
    old_count = c
    i = j2
  }
  if i + 2 > line.length() ||
    line.get_char(i).unwrap() != ' ' ||
    line.get_char(i + 1).unwrap() != '+' {
    return None
  }
  i = i + 2
  guard read_num(i) is Some((new_start, j3)) else { return None }
  i = j3
  let mut new_count = 1
  if i < line.length() && line.get_char(i).unwrap() == ',' {
    guard read_num(i + 1) is Some((c, j4)) else { return None }
    new_count = c
    i = j4
  }
  if i + 3 > line.length() || line[i:i + 3].to_owned() != " @@" {
    return None
  }
  Some((old_start, old_count, new_start, new_count))
}

///|
/// 解析 unified diff 文本为 hunk 序列（忽略 ---/+++ 文件头行；
/// hunk 体行数与头声明不符 / 未知前缀 → None）。
pub fn parse_unified(text : String) -> Array[Hunk]? {
  let lines : Array[String] = []
  let sb = StringBuilder::new()
  for c in text.iter() {
    if c == '\n' {
      lines.push(sb.to_string())
      sb.reset()
    } else {
      sb.write_char(c)
    }
  }
  if sb.to_string().length() > 0 {
    lines.push(sb.to_string())
  }
  let hunks : Array[Hunk] = []
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if line.has_prefix("--- ") || line.has_prefix("+++ ") || line == "" {
      i = i + 1
      continue
    }
    guard parse_hunk_header(line) is Some((os, oc, ns, nc)) else { return None }
    i = i + 1
    let body : Array[DiffOp] = []
    let mut seen_old = 0
    let mut seen_new = 0
    while i < lines.length() && (seen_old < oc || seen_new < nc) {
      let l = lines[i]
      if l.length() == 0 {
        // 空行按空上下文行处理（" " 被剥掉的容错，patch 同款）。
        body.push(Keep(""))
        seen_old = seen_old + 1
        seen_new = seen_new + 1
      } else {
        let tag = l.get_char(0).unwrap()
        let rest = l[1:].to_owned()
        match tag {
          ' ' => {
            body.push(Keep(rest))
            seen_old = seen_old + 1
            seen_new = seen_new + 1
          }
          '-' => {
            body.push(Delete(rest))
            seen_old = seen_old + 1
          }
          '+' => {
            body.push(Insert(rest))
            seen_new = seen_new + 1
          }
          _ => return None
        }
      }
      i = i + 1
    }
    if seen_old != oc || seen_new != nc {
      return None
    }
    hunks.push({
      old_start: os,
      old_count: oc,
      new_start: ns,
      new_count: nc,
      lines: body,
    })
  }
  Some(hunks)
}

///|
/// 应用 hunk 序列到旧文本（行数组）：逐 hunk 按行号定位并校验上下文 /
/// 删除行是否与原文一致，不符返回 None（对标 `patch` 的 reject）。
pub fn apply_unified(
  old : Array[String],
  hunks : Array[Hunk],
) -> Array[String]? {
  let out : Array[String] = []
  let mut cursor = 0 // old 中已消费到的下标
  for h in hunks {
    let hstart = if h.old_count == 0 { h.old_start } else { h.old_start - 1 }
    if hstart < cursor || hstart > old.length() {
      return None
    }
    while cursor < hstart {
      out.push(old[cursor])
      cursor = cursor + 1
    }
    for l in h.lines {
      match l {
        Keep(s) => {
          if cursor >= old.length() || old[cursor] != s {
            return None
          }
          out.push(s)
          cursor = cursor + 1
        }
        Delete(s) => {
          if cursor >= old.length() || old[cursor] != s {
            return None
          }
          cursor = cursor + 1
        }
        Insert(s) => out.push(s)
      }
    }
  }
  while cursor < old.length() {
    out.push(old[cursor])
    cursor = cursor + 1
  }
  Some(out)
}
