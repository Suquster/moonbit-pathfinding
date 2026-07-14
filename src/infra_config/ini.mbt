// ini.mbt —— INI 配置解析。
//
// 约定（业界共识语义，与 Python configparser / git config 对齐）：
// - `[section]` 节头；节前的键归入空名节 ""；
// - `key = value`（也接受 `key: value`），键值两侧空白剔除；
// - 行首 `;` 或 `#` 为注释；空行忽略；
// - 值可用双引号包裹（保留内部空白，剥去引号）；
// - 同节重复键取后者（last-wins）；节保序、节内键保序。
// 畸形行（无 = 或 : 的非空行、未闭合节头）返回 None。
//
// 实现为单趟下标扫描：不切行、不建中间字符数组，只在产出键/值/节名
// 时分配一次字符串。

///|
/// 收缩 [lo, hi) 两端的空格/制表符，返回收缩后的 (lo, hi)。
fn shrink_ws(text : String, lo : Int, hi : Int) -> (Int, Int) {
  let mut l = lo
  let mut h = hi
  while l < h {
    let c = text.unsafe_get(l).to_int()
    if c == 32 || c == 9 {
      l = l + 1
    } else {
      break
    }
  }
  while h > l {
    let c = text.unsafe_get(h - 1).to_int()
    if c == 32 || c == 9 {
      h = h - 1
    } else {
      break
    }
  }
  (l, h)
}

///|
/// 解析 INI 文本 → 保序的 (节名, 保序键值对) 列表。
pub fn ini_parse(text : String) -> Array[(String, Array[(String, String)])]? {
  let sections : Array[(String, Array[(String, String)])] = []
  let mut current : Array[(String, String)] = []
  let mut current_name = ""
  let mut started = false
  let n = text.length()
  let mut pos = 0
  while pos <= n {
    // 行边界：[pos, eol)，兼容 \n 与 \r\n。
    let mut eol = pos
    while eol < n && text.unsafe_get(eol).to_int() != 10 {
      eol = eol + 1
    }
    let mut hi0 = eol
    if hi0 > pos && text.unsafe_get(hi0 - 1).to_int() == 13 {
      hi0 = hi0 - 1
    }
    let (lo, hi) = shrink_ws(text, pos, hi0)
    pos = eol + 1
    if lo >= hi {
      continue
    }
    let head = text.unsafe_get(lo).to_int()
    if head == 59 || head == 35 { // ';' '#'
      continue
    }
    if head == 91 { // '['
      if text.unsafe_get(hi - 1).to_int() != 93 { // ']'
        return None
      }
      if started || current.length() > 0 {
        sections.push((current_name, current))
      }
      let (nl, nh) = shrink_ws(text, lo + 1, hi - 1)
      current_name = text[nl:nh].to_owned()
      current = []
      started = true
      continue
    }
    // key = value 或 key: value（取首个分隔符）。
    let mut sep = -1
    for i in lo..<hi {
      let c = text.unsafe_get(i).to_int()
      if c == 61 || c == 58 { // '=' ':'
        sep = i
        break
      }
    }
    if sep <= lo {
      return None
    }
    let (kl, kh) = shrink_ws(text, lo, sep)
    if kl >= kh {
      return None
    }
    let key = text[kl:kh].to_owned()
    let (vl0, vh0) = shrink_ws(text, sep + 1, hi)
    // 剥去成对双引号。
    let mut vl = vl0
    let mut vh = vh0
    if vh - vl >= 2 &&
      text.unsafe_get(vl).to_int() == 34 &&
      text.unsafe_get(vh - 1).to_int() == 34 {
      vl = vl + 1
      vh = vh - 1
    }
    let value = text[vl:vh].to_owned()
    // last-wins。
    let mut replaced = false
    for i in 0..<current.length() {
      if current[i].0 == key {
        current[i] = (key, value)
        replaced = true
        break
      }
    }
    if !replaced {
      current.push((key, value))
    }
    started = true
  }
  if started || current.length() > 0 {
    sections.push((current_name, current))
  }
  Some(sections)
}

///|
/// 在解析结果里查 (节, 键)。
pub fn ini_get(
  sections : Array[(String, Array[(String, String)])],
  section : String,
  key : String,
) -> String? {
  for s in sections {
    if s.0 == section {
      for kv in s.1 {
        if kv.0 == key {
          return Some(kv.1)
        }
      }
    }
  }
  None
}
