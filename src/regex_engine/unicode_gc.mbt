// unicode_gc.mbt —— Unicode General Category（通用类别）支持（旗舰深化）。
//
// 对应 design.md「Regex 引擎增强设计 §5.1」（Requirement 5.1）。本文件为
// **纯新增（bypass）**，不改动既有 `CharSet`（定义于 nfa.mbt，字段 `intervals`
// 不变），仅在其上构造区间集合，并复用 nfa.mbt 的包内私有归一化原语
// `normalize_intervals`，使产出的 `CharSet` 天然满足「归一化、不相交、升序」
// 不变量，与既有否定字符类补集、DFA 字母表原子区间划分完全同源。
//
// paper-to-code：区间端点取自 The Unicode Standard 的 UnicodeData / Scripts
// 数据（General_Category 字段）。本表覆盖**核心类别**（拉丁字母大小写、若干
// 常见脚本字母、十进制数字、若干数字/标点子类、空白分隔、控制字符），并以
// 命名常量按类别分组组织、逐区间注释来源，不散落 magic number。本表不追求
// 完整 Unicode 覆盖（完整表数千区间，不在本任务范围），未覆盖码点统一归入
// 兜底类别 `Cn`（Unassigned / 未在本核心表登记）。

///|
/// Unicode 通用类别（General Category）。
///
/// 采用 Unicode 标准的两字母缩写命名：首字母为大类（L 字母、N 数字、
/// P 标点、Z 分隔、C 其他），次字母为子类。本枚举覆盖本表用到的核心子类，
/// 并额外提供兜底类别 `Cn`（未分配 / 未在核心表登记）。
pub enum GeneralCategory {
  Lu // Letter, uppercase —— 大写字母
  Ll // Letter, lowercase —— 小写字母
  Lt // Letter, titlecase —— 标题大小写字母
  Lm // Letter, modifier  —— 修饰字母
  Lo // Letter, other     —— 其他字母（如 CJK / 假名 / 谚文）
  Nd // Number, decimal digit —— 十进制数字
  Nl // Number, letter        —— 字母型数字（如罗马数字）
  No // Number, other         —— 其他数字（如上标 / 分数）
  Pc // Punctuation, connector —— 连接标点（如下划线）
  Pd // Punctuation, dash      —— 破折/连字符标点
  Ps // Punctuation, open      —— 开标点（如左括号）
  Pe // Punctuation, close     —— 闭标点（如右括号）
  Po // Punctuation, other     —— 其他标点
  Zs // Separator, space        —— 空格分隔符
  Cc // Other, control          —— 控制字符
  Cn // Other, not assigned     —— 兜底：未分配 / 未在核心表登记
} derive(Eq)

// ───────────────────────── 区间表（命名常量，按类别分组）─────────────────────
//
// 每个常量为该类别在本核心表中覆盖的闭区间序列 `Array[(lo, hi)]`，端点为码点
// （十六进制）。区间互不与其他类别重叠，故按码点查表得到唯一类别。

///|
/// Lu（大写字母）：ASCII A–Z、拉丁补充大写、希腊大写、西里尔大写。
let gc_lu_intervals : Array[(Int, Int)] = [
  (0x0041, 0x005A), // A–Z（Basic Latin）
  (0x00C0, 0x00D6), // À–Ö（Latin-1 Supplement）
  (0x00D8, 0x00DE), // Ø–Þ（Latin-1 Supplement，0x00D7 为乘号 Sm，排除）
  (0x0391, 0x03A1), // Α–Ρ（Greek，0x03A2 为保留空位）
  (0x03A3, 0x03AB), // Σ–Ϋ（Greek）
  (0x0400, 0x042F), // Ѐ–Я（Cyrillic 大写区段）
]

///|
/// Ll（小写字母）：ASCII a–z、微符号、拉丁补充小写、希腊小写、西里尔小写。
let gc_ll_intervals : Array[(Int, Int)] = [
  (0x0061, 0x007A), // a–z（Basic Latin）
  (0x00B5, 0x00B5), // µ 微符号（MICRO SIGN）
  (0x00DF, 0x00F6), // ß–ö（Latin-1 Supplement）
  (0x00F8, 0x00FF), // ø–ÿ（Latin-1 Supplement，0x00F7 为除号 Sm，排除）
  (0x03B1, 0x03C9), // α–ω（Greek）
  (0x0430, 0x044F), // а–я（Cyrillic 小写区段）
  (0x0450, 0x045F), // ѐ–џ（Cyrillic 小写补充）
]

///|
/// Lt（标题大小写字母）：拉丁连字标题形（如 ǅ ǈ ǋ ǲ）。
let gc_lt_intervals : Array[(Int, Int)] = [
  (0x01C5, 0x01C5), // ǅ LATIN CAPITAL LETTER D WITH SMALL LETTER Z WITH CARON
  (0x01C8, 0x01C8), // ǈ LATIN CAPITAL LETTER L WITH SMALL LETTER J
  (0x01CB, 0x01CB), // ǋ LATIN CAPITAL LETTER N WITH SMALL LETTER J
  (0x01F2, 0x01F2), // ǲ LATIN CAPITAL LETTER D WITH SMALL LETTER Z
]

///|
/// Lm（修饰字母）：间距修饰字母常见区段。
let gc_lm_intervals : Array[(Int, Int)] = [
  (0x02B0, 0x02C1), // ʰ–ˁ Spacing Modifier Letters（修饰字母部分）
  (0x02C6, 0x02D1), // ˆ–ˑ Spacing Modifier Letters（修饰字母部分）
]

///|
/// Lo（其他字母）：序数指示符、希伯来/阿拉伯/泰文字母、假名、CJK 统一表意
/// 文字（含扩展 A）、谚文音节。所列区块类别精确为 Lo（已规避其中的修饰符
/// `Lm`、组合记号 `Mn`、标点 `Po` 等非 Lo 码点）。
let gc_lo_intervals : Array[(Int, Int)] = [
  (0x00AA, 0x00AA), // ª FEMININE ORDINAL INDICATOR
  (0x00BA, 0x00BA), // º MASCULINE ORDINAL INDICATOR
  (0x05D0, 0x05EA), // א–ת Hebrew letters
  (0x0621, 0x063A), // Arabic letters（排除 0x0640 Tatweel=Lm）
  (0x0641, 0x064A), // Arabic letters（续）
  (0x0E01, 0x0E2E), // ก–ฮ Thai consonants（排除 0x0E2F Po 与其后 Mn 元音符）
  (0x3041, 0x3096), // ぁ–ゖ Hiragana
  (0x30A1, 0x30FA), // ァ–ヺ Katakana
  (0x3400, 0x4DBF), // CJK Unified Ideographs Extension A
  (0x4E00, 0x9FFF), // 一–鿿 CJK Unified Ideographs
  (0xAC00, 0xD7A3), // 가–힣 Hangul Syllables
]

///|
/// Nd（十进制数字）：ASCII 0–9 及多语言十进制数字块（每块为连续 10 码点，
/// 类别精确为 Nd）。
let gc_nd_intervals : Array[(Int, Int)] = [
  (0x0030, 0x0039), // 0–9（Basic Latin）
  (0x0660, 0x0669), // ٠–٩ Arabic-Indic digits
  (0x06F0, 0x06F9), // ۰–۹ Extended Arabic-Indic digits
  (0x0966, 0x096F), // ०–९ Devanagari digits
  (0x09E6, 0x09EF), // Bengali digits
  (0x0A66, 0x0A6F), // Gurmukhi digits
  (0x0AE6, 0x0AEF), // Gujarati digits
  (0x0B66, 0x0B6F), // Oriya digits
  (0x0BE6, 0x0BEF), // Tamil digits
  (0x0C66, 0x0C6F), // Telugu digits
  (0x0CE6, 0x0CEF), // Kannada digits
  (0x0D66, 0x0D6F), // Malayalam digits
  (0x0E50, 0x0E59), // Thai digits
  (0x0ED0, 0x0ED9), // Lao digits
  (0x0F20, 0x0F29), // Tibetan digits
  (0x1040, 0x1049), // Myanmar digits
  (0x17E0, 0x17E9), // Khmer digits
  (0x1810, 0x1819), // Mongolian digits
  (0xFF10, 0xFF19), // ０–９ Fullwidth digits
]

///|
/// Nl（字母型数字）：罗马数字、表意数字零。
let gc_nl_intervals : Array[(Int, Int)] = [
  (0x2160, 0x2182), // Ⅰ–ↂ Roman numerals（Number Forms）
  (0x3007, 0x3007), // 〇 IDEOGRAPHIC NUMBER ZERO
]

///|
/// No（其他数字）：上标数字、常见分数。
let gc_no_intervals : Array[(Int, Int)] = [
  (0x00B2, 0x00B3), // ²³ SUPERSCRIPT TWO / THREE
  (0x00B9, 0x00B9), // ¹ SUPERSCRIPT ONE
  (0x00BC, 0x00BE), // ¼½¾ VULGAR FRACTION 1/4 1/2 3/4
]

///|
/// Pc（连接标点）：下划线、连接记号。
let gc_pc_intervals : Array[(Int, Int)] = [
  (0x005F, 0x005F), // _ LOW LINE
  (0x203F, 0x2040), // ‿⁀ UNDERTIE / CHARACTER TIE
]

///|
/// Pd（破折/连字符标点）：连字符及各式破折号。
let gc_pd_intervals : Array[(Int, Int)] = [
  (0x002D, 0x002D), // - HYPHEN-MINUS
  (0x2010, 0x2015), // ‐–― 各式连字符与破折号（General Punctuation）
]

///|
/// Ps（开标点）：左圆括号 / 左方括号 / 左花括号。
let gc_ps_intervals : Array[(Int, Int)] = [
  (0x0028, 0x0028), // ( LEFT PARENTHESIS
  (0x005B, 0x005B), // [ LEFT SQUARE BRACKET
  (0x007B, 0x007B), // { LEFT CURLY BRACKET
]

///|
/// Pe（闭标点）：右圆括号 / 右方括号 / 右花括号。
let gc_pe_intervals : Array[(Int, Int)] = [
  (0x0029, 0x0029), // ) RIGHT PARENTHESIS
  (0x005D, 0x005D), // ] RIGHT SQUARE BRACKET
  (0x007D, 0x007D), // } RIGHT CURLY BRACKET
]

///|
/// Po（其他标点）：ASCII 常见标点（排除 Ps/Pe/Pc/Pd 与货币/数学/修饰符号）
/// 及若干拉丁补充标点。
let gc_po_intervals : Array[(Int, Int)] = [
  (0x0021, 0x0023), // ! " #
  (0x0025, 0x0027), // % & '
  (0x002A, 0x002A), // *
  (0x002C, 0x002C), // ,
  (0x002E, 0x002F), // . /
  (0x003A, 0x003B), // : ;
  (0x003F, 0x0040), // ? @
  (0x005C, 0x005C), // \
  (0x00A1, 0x00A1), // ¡ INVERTED EXCLAMATION MARK
  (0x00BF, 0x00BF), // ¿ INVERTED QUESTION MARK
]

///|
/// Zs（空格分隔符）：各式不可见空格分隔符。
let gc_zs_intervals : Array[(Int, Int)] = [
  (0x0020, 0x0020), // SPACE
  (0x00A0, 0x00A0), // NO-BREAK SPACE
  (0x2000, 0x200A), // EN QUAD … HAIR SPACE（General Punctuation 空格族）
  (0x202F, 0x202F), // NARROW NO-BREAK SPACE
  (0x205F, 0x205F), // MEDIUM MATHEMATICAL SPACE
  (0x3000, 0x3000), // IDEOGRAPHIC SPACE
]

///|
/// Cc（控制字符）：C0 与 C1 控制区。
let gc_cc_intervals : Array[(Int, Int)] = [
  (0x0000, 0x001F), // C0 控制字符（含 0x00–0x1F）
  (0x007F, 0x009F), // DELETE 与 C1 控制字符（0x7F–0x9F）
]

///|
/// 取某通用类别在本核心表中的区间序列。`Cn`（兜底）不对应任何登记区间，
/// 返回空序列。
fn gc_intervals_of(gc : GeneralCategory) -> Array[(Int, Int)] {
  match gc {
    Lu => gc_lu_intervals
    Ll => gc_ll_intervals
    Lt => gc_lt_intervals
    Lm => gc_lm_intervals
    Lo => gc_lo_intervals
    Nd => gc_nd_intervals
    Nl => gc_nl_intervals
    No => gc_no_intervals
    Pc => gc_pc_intervals
    Pd => gc_pd_intervals
    Ps => gc_ps_intervals
    Pe => gc_pe_intervals
    Po => gc_po_intervals
    Zs => gc_zs_intervals
    Cc => gc_cc_intervals
    Cn => []
  }
}

///|
/// 本核心表登记的全部类别（按枚举声明序；不含兜底 `Cn`）。用于按码点查表。
let gc_all_categories : Array[GeneralCategory] = [
  Lu,
  Ll,
  Lt,
  Lm,
  Lo,
  Nd,
  Nl,
  No,
  Pc,
  Pd,
  Ps,
  Pe,
  Po,
  Zs,
  Cc,
]

///|
/// 码点 → 通用类别：在区间表中查找 `code` 所属类别。
///
/// 逐类别、逐区间线性查找（核心表区间数为常量级，约数十条）。未被任何登记
/// 区间覆盖的码点返回兜底类别 `Cn`（未分配 / 未在核心表登记）。
pub fn unicode_category(code : Int) -> GeneralCategory {
  for gc in gc_all_categories {
    for iv in gc_intervals_of(gc) {
      let (lo, hi) = iv
      if code >= lo && code <= hi {
        return gc
      }
    }
  }
  Cn
}

///|
/// 通用类别 → `CharSet`：聚合该类别在核心表中的全部区间为一个归一化字符集合。
///
/// 复用 nfa.mbt 的 `normalize_intervals`，产出区间天然满足「归一化、不相交、
/// 升序」不变量。兜底类别 `Cn` 返回空集合。
pub fn category_charset(gc : GeneralCategory) -> CharSet {
  let raw : Array[(Int, Int)] = []
  for iv in gc_intervals_of(gc) {
    raw.push(iv)
  }
  { intervals: normalize_intervals(raw) }
}

///|
/// 将多个类别聚合为单一 `CharSet`（用既有 `CharSet::union` 逐步并集）。
fn union_categories(cats : Array[GeneralCategory]) -> CharSet {
  let mut acc : CharSet = { intervals: [] }
  for gc in cats {
    acc = acc.union(category_charset(gc))
  }
  acc
}

///|
/// 将 `\p{...}` 记法中的类别名映射为对应 `CharSet`。
///
///   * 单字母大类：`L`→Lu/Ll/Lt/Lm/Lo，`N`→Nd/Nl/No，
///     `P`→Pc/Pd/Ps/Pe/Po，`Z`→Zs，`C`→Cc；
///   * 两字母子类：直接对应同名类别；
///   * 其他（含空名 / 未识别）：返回 `None`。
fn charset_of_class_name(name : String) -> CharSet? {
  match name {
    "L" => Some(union_categories([Lu, Ll, Lt, Lm, Lo]))
    "N" => Some(union_categories([Nd, Nl, No]))
    "P" => Some(union_categories([Pc, Pd, Ps, Pe, Po]))
    "Z" => Some(category_charset(Zs))
    "C" => Some(category_charset(Cc))
    "Lu" => Some(category_charset(Lu))
    "Ll" => Some(category_charset(Ll))
    "Lt" => Some(category_charset(Lt))
    "Lm" => Some(category_charset(Lm))
    "Lo" => Some(category_charset(Lo))
    "Nd" => Some(category_charset(Nd))
    "Nl" => Some(category_charset(Nl))
    "No" => Some(category_charset(No))
    "Pc" => Some(category_charset(Pc))
    "Pd" => Some(category_charset(Pd))
    "Ps" => Some(category_charset(Ps))
    "Pe" => Some(category_charset(Pe))
    "Po" => Some(category_charset(Po))
    "Zs" => Some(category_charset(Zs))
    "Cc" => Some(category_charset(Cc))
    _ => None
  }
}

///|
/// 解析 `\p{X}` 记法为 `CharSet`：`X` 为通用类别名（大类如 `L`/`N`，或具体
/// 子类如 `Nd`/`Lu`）。
///
///   * 形如 `\p{NAME}` 且 `NAME` 可识别 → 返回对应 `CharSet`；
///   * 形如不合法（缺前缀 / 缺花括号 / 名不可识别 / 空名）→ 返回 `None`。
///
/// 注：传入的字符串字面量 `"\\p{L}"` 对应实际字符序列 `\ p { L }`。
pub fn parse_unicode_class(spec : String) -> CharSet? {
  let cs = spec.iter().to_array()
  let n = cs.length()
  // 最短合法记法 `\p{X}` 含 5 个字符；不足则非法。
  if n < 5 {
    return None
  }
  // 前缀必须为 `\p{`，末字符必须为 `}`。
  if cs[0] != '\\' || cs[1] != 'p' || cs[2] != '{' || cs[n - 1] != '}' {
    return None
  }
  // 提取花括号内的类别名 `cs[3 .. n-1)`。
  let name_chars : Array[Char] = []
  for i in 3..<(n - 1) {
    name_chars.push(cs[i])
  }
  let name = String::from_array(name_chars)
  charset_of_class_name(name)
}

///|
/// 内联烟雾测试：核心类别查表与字符集合构造（属性测试见任务 5.4）。
test "unicode_gc smoke" {
  // 码点 → 类别。
  assert_true(unicode_category('A'.to_int()) == Lu)
  assert_true(unicode_category('z'.to_int()) == Ll)
  assert_true(unicode_category('5'.to_int()) == Nd)
  assert_true(unicode_category(' '.to_int()) == Zs)
  assert_true(unicode_category(0x00) == Cc)
  assert_true(unicode_category('('.to_int()) == Ps)
  assert_true(unicode_category(')'.to_int()) == Pe)
  assert_true(unicode_category('_'.to_int()) == Pc)
  assert_true(unicode_category('-'.to_int()) == Pd)
  assert_true(unicode_category('!'.to_int()) == Po)
  // 未覆盖码点归入兜底类别 Cn（如 '+' 属 Sm，本核心表不登记）。
  assert_true(unicode_category('+'.to_int()) == Cn)
  // 类别 → CharSet。
  assert_true(category_charset(Nd).contains('5'.to_int()))
  assert_true(category_charset(Lu).contains('A'.to_int()))
  assert_false(category_charset(Lu).contains('a'.to_int()))
  // \p{...} 记法解析。
  let l_class = parse_unicode_class("\\p{L}")
  match l_class {
    Some(cs) => {
      assert_true(cs.contains('A'.to_int()))
      assert_true(cs.contains('z'.to_int()))
      assert_false(cs.contains('5'.to_int()))
    }
    None => assert_true(false)
  }
  let nd_class = parse_unicode_class("\\p{Nd}")
  match nd_class {
    Some(cs) => {
      assert_true(cs.contains('7'.to_int()))
      assert_false(cs.contains('A'.to_int()))
    }
    None => assert_true(false)
  }
  // 未识别记法返回 None。
  assert_true(parse_unicode_class("\\p{Xx}") is None)
  assert_true(parse_unicode_class("L") is None)
}

///|
/// 扩展覆盖核验：新增的多语言 Nd 数字块与 Lo 字母块类别精确，且不与既有区块
/// 冲突（旗舰深化：Unicode GC 表广度扩展，R5）。
test "unicode_gc extended coverage" {
  // 多语言十进制数字（Nd）。
  assert_true(unicode_category(0x09E6) == Nd) // Bengali 0
  assert_true(unicode_category(0x0E50) == Nd) // Thai 0
  assert_true(unicode_category(0x0F29) == Nd) // Tibetan 9
  assert_true(unicode_category(0x1819) == Nd) // Mongolian 9
  // 多语言字母（Lo）。
  assert_true(unicode_category(0x05D0) == Lo) // Hebrew Alef
  assert_true(unicode_category(0x0621) == Lo) // Arabic Hamza
  assert_true(unicode_category(0x0E01) == Lo) // Thai Ko Kai
  assert_true(unicode_category(0x3400) == Lo) // CJK Ext A 起点
  // 规避的非 Lo 码点：阿拉伯 Tatweel(0x0640) 为修饰字母 Lm，不应误判为 Lo。
  assert_false(unicode_category(0x0640) == Lo)
  // \p{Nd} 现含多语言数字；\p{L} 现含希伯来/阿拉伯/泰文字母。
  match parse_unicode_class("\\p{Nd}") {
    Some(cs) => {
      assert_true(cs.contains(0x09EF)) // Bengali 9
      assert_true(cs.contains(0x0E59)) // Thai 9
    }
    None => assert_true(false)
  }
  match parse_unicode_class("\\p{L}") {
    Some(cs) => {
      assert_true(cs.contains(0x05D0)) // Hebrew Alef ∈ L
      assert_true(cs.contains(0x3400)) // CJK Ext A ∈ L
      // Tatweel(0x0640) 既未登记入核心 Lm 表、也已被排除出阿拉伯 Lo 区块，
      // 故归入兜底 Cn，不属 \p{L}。
      assert_false(cs.contains(0x0640))
    }
    None => assert_true(false)
  }
}
