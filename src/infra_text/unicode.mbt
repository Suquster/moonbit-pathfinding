// unicode.mbt —— E6 文本基础设施：Unicode 分析原语。
//
// paper-to-code：
// - 显示宽度：Markus Kuhn `wcwidth()` 参考实现 + UAX #11 *East Asian
//   Width*——East Asian Wide (W) / Fullwidth (F) 记 2 列，控制字符与
//   零宽/组合标记记 0 列，其余记 1 列；
// - 字素簇：UAX #29 *Unicode Text Segmentation* 扩展字素簇规则的
//   生产常用子集——GB3（CR×LF）、GB9（×Extend / ×ZWJ）、GB9a（×
//   SpacingMark 略）、GB11（ZWJ 接续 emoji 序列）、GB12/13（Regional
//   Indicator 成对）、肤色修饰符 U+1F3FB..U+1F3FF 归并；
// - 大小写折叠：Unicode *simple case folding* 的确定性子集——ASCII、
//   Latin-1 补充、希腊、西里尔按码点区间偏移折叠（不做 full folding
//   的一对多展开，例如 ß→ss；范围之外码点原样保留）。
//
// 索引单位：与本包 rope 一致，字素簇边界以 Unicode 码点序列计。

///|
/// 码点是否为零宽的组合/延续类（UAX #29 Extend 的生产常用子集：
/// 组合变音标记、变体选择符、零宽连接/非连接符、肤色修饰符等）。
pub fn is_zero_width_extend(cp : Int) -> Bool {
  (cp >= 0x0300 && cp <= 0x036F) || // Combining Diacritical Marks
  (cp >= 0x0483 && cp <= 0x0489) || // Cyrillic combining
  (cp >= 0x0591 && cp <= 0x05BD) || // Hebrew points
  (cp >= 0x0610 && cp <= 0x061A) || // Arabic marks
  (cp >= 0x064B && cp <= 0x065F) || // Arabic diacritics
  (cp >= 0x1AB0 && cp <= 0x1AFF) || // Combining Diacritical Marks Extended
  (cp >= 0x1DC0 && cp <= 0x1DFF) || // Combining Diacritical Marks Supplement
  cp == 0x200C || // zero width non-joiner
  cp == 0x200D || // zero width joiner
  (cp >= 0x20D0 && cp <= 0x20FF) || // Combining Marks for Symbols
  (cp >= 0xFE00 && cp <= 0xFE0F) || // Variation Selectors
  (cp >= 0xFE20 && cp <= 0xFE2F) || // Combining Half Marks
  (cp >= 0x1F3FB && cp <= 0x1F3FF) // emoji skin tone modifiers
}

///|
/// 码点是否属于 East Asian Wide / Fullwidth（UAX #11 W/F 主要区间，
/// 含 CJK、谚文音节、全角形式与常用宽 emoji 区）。
pub fn is_east_asian_wide(cp : Int) -> Bool {
  (cp >= 0x1100 && cp <= 0x115F) || // Hangul Jamo choseong
  (cp >= 0x2E80 && cp <= 0x303E) || // CJK Radicals .. CJK Symbols
  (cp >= 0x3041 && cp <= 0x33FF) || // Hiragana .. CJK Compatibility
  (cp >= 0x3400 && cp <= 0x4DBF) || // CJK Ext A
  (cp >= 0x4E00 && cp <= 0x9FFF) || // CJK Unified
  (cp >= 0xA000 && cp <= 0xA4CF) || // Yi
  (cp >= 0xAC00 && cp <= 0xD7A3) || // Hangul Syllables
  (cp >= 0xF900 && cp <= 0xFAFF) || // CJK Compatibility Ideographs
  (cp >= 0xFE30 && cp <= 0xFE4F) || // CJK Compatibility Forms
  (cp >= 0xFF00 && cp <= 0xFF60) || // Fullwidth Forms
  (cp >= 0xFFE0 && cp <= 0xFFE6) || // Fullwidth Signs
  (cp >= 0x1F300 && cp <= 0x1F64F) || // emoji: Misc Symbols & Pictographs
  (cp >= 0x1F680 && cp <= 0x1F6FF) || // emoji: Transport
  (cp >= 0x1F900 && cp <= 0x1F9FF) || // emoji: Supplemental Symbols
  (cp >= 0x20000 && cp <= 0x2FFFD) || // CJK Ext B..F
  (cp >= 0x30000 && cp <= 0x3FFFD) // CJK Ext G
}

///|
/// 单码点显示列宽（wcwidth 语义）：控制字符与零宽类 0 列、
/// East Asian Wide/Fullwidth 2 列、其余 1 列。
pub fn codepoint_width(cp : Int) -> Int {
  if cp == 0 {
    0
  } else if cp < 0x20 || (cp >= 0x7F && cp < 0xA0) {
    0 // C0/C1 控制字符（wcwidth 对其返回 -1，本 API 归 0 列）
  } else if is_zero_width_extend(cp) {
    0
  } else if is_east_asian_wide(cp) {
    2
  } else {
    1
  }
}

///|
/// 字符串显示总列宽（wcswidth 语义）：逐码点求和。
pub fn display_width(s : String) -> Int {
  let mut w = 0
  for c in s.iter() {
    w = w + codepoint_width(c.to_int())
  }
  w
}

///|
/// Regional Indicator（国旗对，U+1F1E6..U+1F1FF）。
fn is_regional_indicator(cp : Int) -> Bool {
  cp >= 0x1F1E6 && cp <= 0x1F1FF
}

///|
/// 把字符串切分为扩展字素簇（UAX #29 生产常用子集）：
/// CR LF 归一簇；Extend/ZWJ/肤色修饰符并入前簇；ZWJ 后的下一码点
/// 接续 emoji 序列（GB11）；Regional Indicator 两两成对（GB12/13）。
pub fn grapheme_clusters(s : String) -> Array[String] {
  let cps = s.iter().to_array()
  let out : Array[String] = []
  let n = cps.length()
  let mut i = 0
  while i < n {
    let sb = StringBuilder::new()
    let c0 = cps[i]
    sb.write_char(c0)
    i = i + 1
    // GB3：CR × LF。
    if c0 == '\r' && i < n && cps[i] == '\n' {
      sb.write_char('\n')
      i = i + 1
      out.push(sb.to_string())
      continue
    }
    // GB12/13：Regional Indicator 两两成对。
    if is_regional_indicator(c0.to_int()) &&
      i < n &&
      is_regional_indicator(cps[i].to_int()) {
      sb.write_char(cps[i])
      i = i + 1
    }
    // GB9/GB11：吸收 Extend / 肤色修饰符；ZWJ 则再接续下一码点。
    while i < n {
      let cp = cps[i].to_int()
      if is_zero_width_extend(cp) {
        sb.write_char(cps[i])
        i = i + 1
        if cp == 0x200D && i < n {
          // GB11：ZWJ 接续 emoji 序列的下一元素。
          sb.write_char(cps[i])
          i = i + 1
        }
      } else {
        break
      }
    }
    out.push(sb.to_string())
  }
  out
}

///|
/// 字素簇个数（用户可感知字符数）。
pub fn grapheme_count(s : String) -> Int {
  grapheme_clusters(s).length()
}

///|
/// 单码点 simple case folding（确定性子集：ASCII、Latin-1 补充、
/// 希腊、西里尔；范围之外原样返回）。
pub fn fold_codepoint(cp : Int) -> Int {
  if cp >= 0x41 && cp <= 0x5A {
    cp + 32 // ASCII A-Z
  } else if cp >= 0xC0 && cp <= 0xDE && cp != 0xD7 {
    cp + 32 // Latin-1 À-Þ（乘号 × 除外）
  } else if cp >= 0x391 && cp <= 0x3A9 && cp != 0x3A2 {
    cp + 32 // 希腊 Α-Ω（0x3A2 为空位）
  } else if cp >= 0x410 && cp <= 0x42F {
    cp + 32 // 西里尔 А-Я
  } else if cp >= 0x400 && cp <= 0x40F {
    cp + 80 // 西里尔 Ѐ-Џ → ѐ-џ
  } else {
    cp
  }
}

///|
/// 字符串 simple case folding：逐码点应用 `fold_codepoint`。
/// 用于大小写不敏感比较（fold(a) == fold(b)）。
pub fn case_fold(s : String) -> String {
  let sb = StringBuilder::new()
  for c in s.iter() {
    match fold_codepoint(c.to_int()).to_char() {
      Some(f) => sb.write_char(f)
      None => sb.write_char(c) // 理论不可达：折叠不会产生非法码点
    }
  }
  sb.to_string()
}

///|
/// 大小写不敏感相等（simple case folding 语义）。
pub fn eq_fold(a : String, b : String) -> Bool {
  case_fold(a) == case_fold(b)
}
