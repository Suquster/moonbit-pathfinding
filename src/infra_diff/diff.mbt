// diff.mbt —— Myers diff / patch 应用 / SemVer 2.0.0。
//
// paper-to-code：
// - Myers. *An O(ND) Difference Algorithm and Its Variations.*
//   Algorithmica 1986：贪心对角线搜索最短编辑脚本（SES），V 数组按
//   编辑距离 d 逐层扩展 k 对角线（k ∈ [-d, d]），trace 回溯重建脚本；
//   时间 O((N+M)·D)、空间 O((N+M)·D)（保留各层 V 以便回溯）；
// - patch：编辑脚本的正向应用（old → new）与逆向应用（new → old，
//   Insert/Delete 对偶互换），应用前校验上下文行匹配；
// - SemVer 2.0.0（https://semver.org）：`MAJOR.MINOR.PATCH[-prerelease][+build]`
//   解析；优先级比较实现规范 §11（数值段数值比较、字母段 ASCII 比较、
//   预发布 < 正式版、build 元数据不参与比较）。

///|
/// 编辑操作（行粒度）。
pub(all) enum DiffOp {
  Keep(String) // 两侧共有
  Delete(String) // 仅旧侧
  Insert(String) // 仅新侧
} derive(Eq, Debug)

///|
/// 诊断输出（统一 diff 前缀风格）。
pub impl Show for DiffOp with fn output(self, logger) {
  match self {
    Keep(s) => logger.write_string("  " + s)
    Delete(s) => logger.write_string("- " + s)
    Insert(s) => logger.write_string("+ " + s)
  }
}

///|
/// Myers O(ND) 最短编辑脚本。
pub fn diff_lines(old : Array[String], new : Array[String]) -> Array[DiffOp] {
  let n = old.length()
  let m = new.length()
  let max = n + m
  if max == 0 {
    return []
  }
  // V[k+offset] = 该对角线上最远 x。保留每层快照供回溯。
  let offset = max
  let width = 2 * max + 1
  let trace : Array[Array[Int]] = []
  let v : Array[Int] = Array::make(width, 0)
  let mut found_d = -1
  for d in 0..<=max {
    let mut k = -d
    while k <= d {
      let idx = k + offset
      let mut x = if k == -d || (k != d && v[idx - 1] < v[idx + 1]) {
        v[idx + 1] // 向下（Insert）
      } else {
        v[idx - 1] + 1 // 向右（Delete）
      }
      let mut y = x - k
      while x < n && y < m && old[x] == new[y] {
        x = x + 1
        y = y + 1
      }
      v[idx] = x
      if x >= n && y >= m {
        found_d = d
        break
      }
      k = k + 2
    }
    trace.push(v.copy())
    if found_d >= 0 {
      break
    }
  }
  // 回溯重建脚本。
  let ops_rev : Array[DiffOp] = []
  let mut x = n
  let mut y = m
  let mut d = found_d
  while d > 0 {
    let prev_v = trace[d - 1]
    let k = x - y
    let idx = k + offset
    let go_down = k == -d || (k != d && prev_v[idx - 1] < prev_v[idx + 1])
    let prev_k = if go_down { k + 1 } else { k - 1 }
    let prev_x = prev_v[prev_k + offset]
    let prev_y = prev_x - prev_k
    // 先回吐 snake（对角线共同行）。
    while x > prev_x + (if go_down { 0 } else { 1 }) &&
          y > prev_y + (if go_down { 1 } else { 0 }) {
      x = x - 1
      y = y - 1
      ops_rev.push(Keep(old[x]))
    }
    if go_down {
      y = y - 1
      ops_rev.push(Insert(new[y]))
    } else {
      x = x - 1
      ops_rev.push(Delete(old[x]))
    }
    d = d - 1
  }
  // d=0 层剩余 snake。
  while x > 0 && y > 0 {
    x = x - 1
    y = y - 1
    ops_rev.push(Keep(old[x]))
  }
  let ops : Array[DiffOp] = []
  let mut i = ops_rev.length() - 1
  while i >= 0 {
    ops.push(ops_rev[i])
    i = i - 1
  }
  ops
}

///|
/// 正向应用（old → new）；上下文行不匹配返回 None。
pub fn patch_apply(old : Array[String], ops : Array[DiffOp]) -> Array[String]? {
  let out : Array[String] = []
  let mut i = 0
  for op in ops {
    match op {
      Keep(s) => {
        if i >= old.length() || old[i] != s {
          return None
        }
        out.push(s)
        i = i + 1
      }
      Delete(s) => {
        if i >= old.length() || old[i] != s {
          return None
        }
        i = i + 1
      }
      Insert(s) => out.push(s)
    }
  }
  if i != old.length() {
    return None
  }
  Some(out)
}

///|
/// 逆向应用（new → old）：Insert/Delete 对偶互换。
pub fn patch_revert(new : Array[String], ops : Array[DiffOp]) -> Array[String]? {
  let inverted : Array[DiffOp] = []
  for op in ops {
    match op {
      Keep(s) => inverted.push(Keep(s))
      Delete(s) => inverted.push(Insert(s))
      Insert(s) => inverted.push(Delete(s))
    }
  }
  patch_apply(new, inverted)
}

///|
/// 编辑距离（Delete + Insert 计数）。
pub fn edit_distance(ops : Array[DiffOp]) -> Int {
  let mut d = 0
  for op in ops {
    match op {
      Keep(_) => ()
      _ => d = d + 1
    }
  }
  d
}

///|
/// SemVer 2.0.0 版本。
pub(all) struct SemVer {
  major : Int
  minor : Int
  patch : Int
  prerelease : Array[String] // '.' 分段
  build : String // build 元数据（不参与比较）
} derive(Eq, Debug)

///|
/// 诊断输出。
pub impl Show for SemVer with fn output(self, logger) {
  let mut s = "\{self.major}.\{self.minor}.\{self.patch}"
  if self.prerelease.length() > 0 {
    let mut pre = ""
    for i, seg in self.prerelease {
      if i > 0 {
        pre = pre + "."
      }
      pre = pre + seg
    }
    s = s + "-" + pre
  }
  if self.build != "" {
    s = s + "+" + self.build
  }
  logger.write_string(s)
}

///|
/// 段是否为纯数字。
fn all_digits(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for c in s.iter() {
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
/// 数字段解析（拒绝前导零，SemVer §2/§9）。
fn parse_numeric(s : String) -> Int? {
  if !all_digits(s) {
    return None
  }
  let chars = s.iter().to_array()
  if chars.length() > 1 && chars[0] == '0' {
    return None
  }
  let mut acc = 0
  for c in chars {
    acc = acc * 10 + (c.to_int() - 48)
  }
  Some(acc)
}

///|
/// 按分隔符切分。
fn split_on(s : String, sep : Char) -> Array[String] {
  let parts : Array[String] = []
  let sb = StringBuilder::new()
  for c in s.iter() {
    if c == sep {
      parts.push(sb.to_string())
      sb.reset()
    } else {
      sb.write_char(c)
    }
  }
  parts.push(sb.to_string())
  parts
}

///|
/// 解析 SemVer 2.0.0：`MAJOR.MINOR.PATCH[-pre.release][+build]`；
/// 畸形（缺段 / 前导零 / 空段 / 非法字符）返回 None。
pub fn semver_parse(text : String) -> SemVer? {
  // 先剥 build 元数据。
  let plus_parts = split_on(text, '+')
  if plus_parts.length() > 2 {
    return None
  }
  let build = if plus_parts.length() == 2 { plus_parts[1] } else { "" }
  if plus_parts.length() == 2 && build.length() == 0 {
    return None
  }
  // 再剥预发布（第一个 '-' 之后全部）。
  let core_pre = plus_parts[0]
  let dash_parts = split_on(core_pre, '-')
  let core = dash_parts[0]
  let mut pre_text = ""
  if dash_parts.length() > 1 {
    let sb = StringBuilder::new()
    for i in 1..<dash_parts.length() {
      if i > 1 {
        sb.write_char('-')
      }
      sb.write_string(dash_parts[i])
    }
    pre_text = sb.to_string()
    if pre_text.length() == 0 {
      return None
    }
  }
  // 核心三段。
  let nums = split_on(core, '.')
  if nums.length() != 3 {
    return None
  }
  let major = match parse_numeric(nums[0]) {
    Some(v) => v
    None => return None
  }
  let minor = match parse_numeric(nums[1]) {
    Some(v) => v
    None => return None
  }
  let patch = match parse_numeric(nums[2]) {
    Some(v) => v
    None => return None
  }
  // 预发布段校验：非空、字符集 [0-9A-Za-z-]、数字段无前导零。
  let prerelease : Array[String] = []
  if pre_text != "" {
    for seg in split_on(pre_text, '.') {
      if seg.length() == 0 {
        return None
      }
      for c in seg.iter() {
        let ok = (c >= '0' && c <= '9') ||
          (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          c == '-'
        if !ok {
          return None
        }
      }
      if all_digits(seg) && parse_numeric(seg) == None {
        return None // 数字段前导零
      }
      prerelease.push(seg)
    }
  }
  Some({ major, minor, patch, prerelease, build })
}

///|
/// 优先级比较（SemVer §11）：-1 / 0 / 1。build 元数据不参与。
pub fn semver_compare(a : SemVer, b : SemVer) -> Int {
  if a.major != b.major {
    return if a.major < b.major { -1 } else { 1 }
  }
  if a.minor != b.minor {
    return if a.minor < b.minor { -1 } else { 1 }
  }
  if a.patch != b.patch {
    return if a.patch < b.patch { -1 } else { 1 }
  }
  // 预发布 < 正式版。
  if a.prerelease.length() == 0 && b.prerelease.length() == 0 {
    return 0
  }
  if a.prerelease.length() == 0 {
    return 1
  }
  if b.prerelease.length() == 0 {
    return -1
  }
  let n = if a.prerelease.length() < b.prerelease.length() {
    a.prerelease.length()
  } else {
    b.prerelease.length()
  }
  for i in 0..<n {
    let x = a.prerelease[i]
    let y = b.prerelease[i]
    if x == y {
      continue
    }
    let xd = all_digits(x)
    let yd = all_digits(y)
    if xd && yd {
      let xv = parse_numeric(x).unwrap()
      let yv = parse_numeric(y).unwrap()
      return if xv < yv { -1 } else { 1 }
    }
    // 数值段优先级低于字母段。
    if xd {
      return -1
    }
    if yd {
      return 1
    }
    return if x < y { -1 } else { 1 }
  }
  // 前缀相同，段多者优先级高。
  if a.prerelease.length() == b.prerelease.length() {
    0
  } else if a.prerelease.length() < b.prerelease.length() {
    -1
  } else {
    1
  }
}
