// unicode_gc.mbt —— Unicode General Category（通用类别）完整支持。
//
// 对应 design.md「Regex 引擎增强设计 §5.1」（Requirement 5.1）。本文件为
// **纯新增（bypass）**，不改动既有 `CharSet`（定义于 nfa.mbt，字段 `intervals`
// 不变），仅在其上构造区间集合，并复用 nfa.mbt 的包内私有归一化原语
// `normalize_intervals`，使产出的 `CharSet` 天然满足「归一化、不相交、升序」
// 不变量，与既有否定字符类补集、DFA 字母表原子区间划分完全同源。
//
// paper-to-code：区间表由 UCD 16.0 UnicodeData.txt 的 General_Category 字段
// 机器生成（unicode_gc_table.mbt，29 个已赋值类别、3414 条升序闭区间，
// 含 <First>/<Last> 范围行展开），覆盖全部已分配码点；未分配码点归入
// `Cn`（= 全域对已赋值类别并集的补集）。查表按类别二分定位，
// 与 RE2/Rust `regex` 的 `\p{...}` 支持同水位。

///|
/// Unicode 通用类别（General Category）。
///
/// 采用 Unicode 标准的两字母缩写命名：首字母为大类（L 字母、M 记号、
/// N 数字、P 标点、S 符号、Z 分隔、C 其他），次字母为子类。覆盖 UCD 的
/// 全部 30 个类别（29 个已赋值类别 + 未分配 `Cn`）。
pub enum GeneralCategory {
  Lu // Letter, uppercase —— 大写字母
  Ll // Letter, lowercase —— 小写字母
  Lt // Letter, titlecase —— 标题大小写字母
  Lm // Letter, modifier  —— 修饰字母
  Lo // Letter, other     —— 其他字母（如 CJK / 假名 / 谚文）
  Mn // Mark, nonspacing      —— 非间距组合记号
  Mc // Mark, spacing combining —— 间距组合记号
  Me // Mark, enclosing       —— 包围记号
  Nd // Number, decimal digit —— 十进制数字
  Nl // Number, letter        —— 字母型数字（如罗马数字）
  No // Number, other         —— 其他数字（如上标 / 分数）
  Pc // Punctuation, connector —— 连接标点（如下划线）
  Pd // Punctuation, dash      —— 破折/连字符标点
  Ps // Punctuation, open      —— 开标点（如左括号）
  Pe // Punctuation, close     —— 闭标点（如右括号）
  Pi // Punctuation, initial quote —— 前引号
  Pf // Punctuation, final quote   —— 后引号
  Po // Punctuation, other     —— 其他标点
  Sm // Symbol, math     —— 数学符号
  Sc // Symbol, currency —— 货币符号
  Sk // Symbol, modifier —— 修饰符号
  So // Symbol, other    —— 其他符号
  Zs // Separator, space     —— 空格分隔符
  Zl // Separator, line      —— 行分隔符
  Zp // Separator, paragraph —— 段分隔符
  Cc // Other, control      —— 控制字符
  Cf // Other, format       —— 格式字符
  Co // Other, private use  —— 私用区
  Cs // Other, surrogate    —— 代理码点
  Cn // Other, not assigned —— 未分配
} derive(Eq)

///|
/// 取某通用类别的生成区间表（升序闭区间对平铺数组）。`Cn`（未分配）
/// 无登记区间，返回空表（其集合以补集构造，见 `category_charset`）。
fn gc_table_of(gc : GeneralCategory) -> Array[Int] {
  match gc {
    Lu => gc_tab_lu
    Ll => gc_tab_ll
    Lt => gc_tab_lt
    Lm => gc_tab_lm
    Lo => gc_tab_lo
    Mn => gc_tab_mn
    Mc => gc_tab_mc
    Me => gc_tab_me
    Nd => gc_tab_nd
    Nl => gc_tab_nl
    No => gc_tab_no
    Pc => gc_tab_pc
    Pd => gc_tab_pd
    Ps => gc_tab_ps
    Pe => gc_tab_pe
    Pi => gc_tab_pi
    Pf => gc_tab_pf
    Po => gc_tab_po
    Sm => gc_tab_sm
    Sc => gc_tab_sc
    Sk => gc_tab_sk
    So => gc_tab_so
    Zs => gc_tab_zs
    Zl => gc_tab_zl
    Zp => gc_tab_zp
    Cc => gc_tab_cc
    Cf => gc_tab_cf
    Co => gc_tab_co
    Cs => gc_tab_cs
    Cn => []
  }
}

///|
/// 全部已赋值类别（按枚举声明序；不含未分配 `Cn`）。用于按码点查表。
let gc_all_categories : Array[GeneralCategory] = [
  Lu,
  Ll,
  Lt,
  Lm,
  Lo,
  Mn,
  Mc,
  Me,
  Nd,
  Nl,
  No,
  Pc,
  Pd,
  Ps,
  Pe,
  Pi,
  Pf,
  Po,
  Sm,
  Sc,
  Sk,
  So,
  Zs,
  Zl,
  Zp,
  Cc,
  Cf,
  Co,
  Cs,
]

///|
/// 在某类别的升序区间表中二分查找码点归属。
fn gc_table_contains(tab : Array[Int], code : Int) -> Bool {
  let m = tab.length() / 2
  let mut l = 0
  let mut r = m
  while l < r {
    let mid = (l + r) / 2
    if tab[2 * mid + 1] < code {
      l = mid + 1
    } else {
      r = mid
    }
  }
  l < m && tab[2 * l] <= code && code <= tab[2 * l + 1]
}

///|
/// 码点 → 通用类别：逐类别二分定位（各类别区间互不重叠，命中唯一）。
/// 未被任何已赋值区间覆盖的码点返回 `Cn`（未分配）。
pub fn unicode_category(code : Int) -> GeneralCategory {
  for gc in gc_all_categories {
    if gc_table_contains(gc_table_of(gc), code) {
      return gc
    }
  }
  Cn
}

///|
/// 通用类别 → `CharSet`：聚合该类别全部区间为一个归一化字符集合。
///
/// 复用 nfa.mbt 的 `normalize_intervals`，产出区间天然满足「归一化、不相交、
/// 升序」不变量。`Cn`（未分配）= 全域对全部已赋值类别并集的补集。
pub fn category_charset(gc : GeneralCategory) -> CharSet {
  match gc {
    Cn => {
      let mut assigned : CharSet = { intervals: [] }
      for c in gc_all_categories {
        assigned = assigned.union(category_charset(c))
      }
      assigned.complement()
    }
    _ => {
      let tab = gc_table_of(gc)
      let raw : Array[(Int, Int)] = []
      let mut i = 0
      while i < tab.length() {
        raw.push((tab[i], tab[i + 1]))
        i = i + 2
      }
      { intervals: normalize_intervals(raw) }
    }
  }
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
///   * 单字母大类：`L`→Lu/Ll/Lt/Lm/Lo，`M`→Mn/Mc/Me，`N`→Nd/Nl/No，
///     `P`→Pc/Pd/Ps/Pe/Pi/Pf/Po，`S`→Sm/Sc/Sk/So，`Z`→Zs/Zl/Zp，
///     `C`→Cc/Cf/Co/Cs/Cn；
///   * 两字母子类：直接对应同名类别（全部 30 个，含 `Cn`）；
///   * 其他（含空名 / 未识别）：返回 `None`。
fn charset_of_class_name(name : String) -> CharSet? {
  match name {
    "L" => Some(union_categories([Lu, Ll, Lt, Lm, Lo]))
    "M" => Some(union_categories([Mn, Mc, Me]))
    "N" => Some(union_categories([Nd, Nl, No]))
    "P" => Some(union_categories([Pc, Pd, Ps, Pe, Pi, Pf, Po]))
    "S" => Some(union_categories([Sm, Sc, Sk, So]))
    "Z" => Some(union_categories([Zs, Zl, Zp]))
    "C" => Some(union_categories([Cc, Cf, Co, Cs, Cn]))
    "Lu" => Some(category_charset(Lu))
    "Ll" => Some(category_charset(Ll))
    "Lt" => Some(category_charset(Lt))
    "Lm" => Some(category_charset(Lm))
    "Lo" => Some(category_charset(Lo))
    "Mn" => Some(category_charset(Mn))
    "Mc" => Some(category_charset(Mc))
    "Me" => Some(category_charset(Me))
    "Nd" => Some(category_charset(Nd))
    "Nl" => Some(category_charset(Nl))
    "No" => Some(category_charset(No))
    "Pc" => Some(category_charset(Pc))
    "Pd" => Some(category_charset(Pd))
    "Ps" => Some(category_charset(Ps))
    "Pe" => Some(category_charset(Pe))
    "Pi" => Some(category_charset(Pi))
    "Pf" => Some(category_charset(Pf))
    "Po" => Some(category_charset(Po))
    "Sm" => Some(category_charset(Sm))
    "Sc" => Some(category_charset(Sc))
    "Sk" => Some(category_charset(Sk))
    "So" => Some(category_charset(So))
    "Zs" => Some(category_charset(Zs))
    "Zl" => Some(category_charset(Zl))
    "Zp" => Some(category_charset(Zp))
    "Cc" => Some(category_charset(Cc))
    "Cf" => Some(category_charset(Cf))
    "Co" => Some(category_charset(Co))
    "Cs" => Some(category_charset(Cs))
    "Cn" => Some(category_charset(Cn))
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
  assert_true(unicode_category('+'.to_int()) == Sm)
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
/// 扩展覆盖核验：多语言 Nd 数字块与 Lo 字母块类别精确，全表覆盖下
/// Tatweel 等修饰字母归类正确。
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
  // 阿拉伯 Tatweel(0x0640) 为修饰字母 Lm。
  assert_true(unicode_category(0x0640) == Lm)
  // \p{Nd} 含多语言数字；\p{L} 含希伯来/阿拉伯/泰文字母与 Lm。
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
      assert_true(cs.contains(0x0640)) // Tatweel(Lm) ∈ L
    }
    None => assert_true(false)
  }
}
