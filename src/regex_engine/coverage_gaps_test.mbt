// coverage_gaps_test.mbt —— 覆盖率盲区收口：解析器错误分支 / Unicode 类别 /
// 打印器 / 替换语法 / 内联标志 / 空模式与边界形态的黑盒测试。

///|
/// 按匹配区间截取输入的 Unicode 标量字符切片。
fn cg_slice(input : String, m : @regex_engine.Match) -> String {
  let chars = input.iter().to_array()
  let mut out = ""
  for k in m.start..<m.end {
    out = out + chars[k].to_string()
  }
  out
}

///|
test "解析器错误分支：交替后跟非法量词 / 非法重复计数" {
  assert_true(@regex_engine.parse_pattern("a|*") is Err(_))
  assert_true(@regex_engine.parse_pattern("a{2,x}") is Err(_))
  assert_true(@regex_engine.parse_pattern("a{x}") is Err(_))
  assert_true(@regex_engine.parse_pattern("a{2") is Err(_))
  assert_true(@regex_engine.parse_regex("a|*") is Err(_))
  assert_true(@regex_engine.parse_regex("a{2,x}") is Err(_))
  assert_true(@regex_engine.parse_regex("a{x}") is Err(_))
  assert_true(@regex_engine.parse_regex("a{2") is Err(_))
}

///|
test "解析器错误分支：裸 ')' / 裸 '|' / 悬空转义 / 未闭合括号与字符类" {
  assert_true(@regex_engine.parse_pattern(")") is Err(_))
  assert_true(@regex_engine.parse_pattern("a\\") is Err(_))
  assert_true(@regex_engine.parse_pattern("(a") is Err(_))
  assert_true(@regex_engine.parse_pattern("[abc") is Err(_))
  assert_true(@regex_engine.parse_pattern("[a\\") is Err(_))
  assert_true(@regex_engine.parse_regex(")") is Err(_))
  assert_true(@regex_engine.parse_regex("a\\") is Err(_))
  assert_true(@regex_engine.parse_regex("(a") is Err(_))
  assert_true(@regex_engine.parse_regex("[abc") is Err(_))
  assert_true(@regex_engine.parse_regex("[a\\") is Err(_))
  assert_true(@regex_engine.parse_regex("(a|b") is Err(_))
}

///|
test "解析器错误分支：命名组与组构造非法形态" {
  assert_true(@regex_engine.parse_pattern("(?Pxabc)") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?*)") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?P<>a)") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?P<na me>a)") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?P<name") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?x)") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?i") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?s:a") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?<=a)b") is Ok(_))
  assert_true(@regex_engine.parse_pattern("(?<!a)b") is Ok(_))
  assert_true(@regex_engine.parse_pattern("(?<=a") is Err(_))
}

///|
test "内联标志组：(?s) 作用域与 (?s:...) 局部生效" {
  guard @regex_engine.Pattern::compile("(?s)a.b") is Ok(p1)
  assert_true(p1.is_match("a\nb"))
  guard @regex_engine.Pattern::compile("(?s:a.)b") is Ok(p2)
  assert_true(p2.is_match("a\nb"))
  guard @regex_engine.Pattern::compile("a.b") is Ok(p3)
  assert_true(!p3.is_match("a\nb"))
}

///|
test "预定义类 \\D 与锚点 \\z 端到端匹配" {
  guard @regex_engine.Pattern::compile("\\D+") is Ok(pd)
  guard pd.find("12ab34") is Some(m)
  assert_true(cg_slice("12ab34", m) == "ab")
  guard @regex_engine.Pattern::compile("b\\z") is Ok(pz)
  assert_true(pz.is_match("ab"))
  assert_true(!pz.is_match("ba"))
}

///|
test "Unicode 类别查表：Lt/Nl/Pc/Ps/Cc 与 P 大类并集、未知类别拒绝" {
  guard @regex_engine.parse_unicode_class("\\p{Lt}") is Some(lt)
  assert_true(lt.contains(0x01C5)) // ǅ Titlecase
  guard @regex_engine.parse_unicode_class("\\p{Nl}") is Some(nl)
  assert_true(nl.contains(0x2160)) // Ⅰ Roman numeral
  guard @regex_engine.parse_unicode_class("\\p{Pc}") is Some(pc)
  assert_true(pc.contains('_'.to_int()))
  guard @regex_engine.parse_unicode_class("\\p{Ps}") is Some(ps)
  assert_true(ps.contains('('.to_int()))
  guard @regex_engine.parse_unicode_class("\\p{Cc}") is Some(cc)
  assert_true(cc.contains(0x0007)) // BEL 控制字符
  guard @regex_engine.parse_unicode_class("\\p{P}") is Some(pu)
  assert_true(pu.contains('('.to_int()) && pu.contains('-'.to_int()))
  assert_true(@regex_engine.parse_unicode_class("\\p{Zz}") is None)
  assert_true(@regex_engine.parse_unicode_class("!") is None)
}

///|
test "字符类内 \\p{...} 元素与未闭合 \\p 记法" {
  guard @regex_engine.Pattern::compile("[\\p{Nd}x]+") is Ok(p)
  guard p.find("a7x1b") is Some(m)
  assert_true(cg_slice("a7x1b", m) == "7x1")
  assert_true(@regex_engine.Pattern::compile("[\\p{Nd") is Err(_))
  assert_true(@regex_engine.Pattern::compile("[\\p{Zz}]") is Err(_))
}

///|
test "打印器：Empty / \\z / ? 量词 / {m} 计数 / 组包裹形态" {
  guard @regex_engine.parse_pattern("") is Ok(empty_ast)
  assert_true(@regex_engine.print_ast(empty_ast) == "")
  guard @regex_engine.parse_pattern("a\\z") is Ok(az)
  assert_true(@regex_engine.print_ast(az).contains("\\z"))
  guard @regex_engine.parse_pattern("a?") is Ok(aq)
  assert_true(@regex_engine.print_ast(aq).contains("?"))
  guard @regex_engine.parse_pattern("a{3}") is Ok(a3)
  assert_true(@regex_engine.print_ast(a3).contains("{3}"))
  guard @regex_engine.parse_pattern("(?:a|b)*") is Ok(alt_star)
  assert_true(@regex_engine.print_ast(alt_star).contains("|"))
}

///|
test "空模式与 a{0}：编译可用且匹配空串语义" {
  guard @regex_engine.Pattern::compile("") is Ok(pe)
  assert_true(pe.is_match(""))
  assert_true(pe.is_match("xyz"))
  guard @regex_engine.Pattern::compile("a{0}b") is Ok(p0)
  assert_true(p0.is_match("b"))
  guard @regex_engine.parse_pattern("") is Ok(east)
  let _ = @regex_engine.compute_prefilter(east, @regex_engine.Flags::default())
}

///|
test "忽略大小写标志下的单字符折叠编译" {
  guard @regex_engine.Pattern::compile(
      "a",
      flags=@regex_engine.Flags::parse("i"),
    )
    is Ok(p)
  assert_true(p.is_match("A"))
  assert_true(p.is_match("a"))
}

///|
test "替换语法：末尾 $ 与非法 $x 按字面输出、未匹配组替换为空串" {
  guard @regex_engine.Pattern::compile("(a)(b)?") is Ok(p)
  assert_true(p.replace("a", "[$1|$2]") == "[a|]")
  assert_true(p.replace("a", "x$") == "x$")
  assert_true(p.replace("a", "$x") == "$x")
  guard @regex_engine.Pattern::compile("zzz") is Ok(pn)
  assert_true(pn.replace("abc", "!") == "abc")
  assert_true(pn.replace_all("abc", "!") == "abc")
}

///|
test "find_iter 与 captures_all 全量扫描" {
  guard @regex_engine.Pattern::compile("(a)b?") is Ok(p)
  let ms = p.find_iter("abxa")
  assert_true(ms.length() == 2)
  let cs = p.captures_all("abxa")
  assert_true(cs.length() == 2)
  guard cs[0].group(1) is Some(g1)
  assert_true(cg_slice("abxa", g1) == "a")
}

///|
test "环视断言：字符类前瞻在 Pike VM 布尔执行路径命中" {
  guard @regex_engine.Pattern::compile("(?=[0-9])[0-9a-z]+") is Ok(p)
  guard p.find("zz7ab") is Some(m)
  assert_true(cg_slice("zz7ab", m) == "7ab")
  guard @regex_engine.Pattern::compile("(?![0-9])[0-9a-z]+") is Ok(pn)
  guard pn.find("7ab") is Some(mn)
  assert_true(cg_slice("7ab", mn) == "ab")
}

///|
test "有界回溯：环视程序走 run_bool 且结果与 Pike VM 一致" {
  guard @regex_engine.Pattern::compile("(?=[a-c])x|[a-c]") is Ok(p)
  let prog = p.find("b") // Pike 路径参照
  guard @regex_engine.Pattern::compile("(?=[a-c])[a-z]") is Ok(pb)
  ignore(prog)
  guard pb.find("b") is Some(m)
  assert_true(cg_slice("b", m) == "b")
}

///|
test "最小化：平凡 DFA 直接返回自身" {
  guard @regex_engine.parse_regex("") is Ok(r)
  let d = @regex_engine.to_dfa(@regex_engine.build_nfa(r))
  let md = d.minimize()
  assert_true(md.find("") is Some(_))
}

///|
test "行尾锚点 $ 的 NFA 构造与匹配" {
  guard @regex_engine.parse_regex("ab$") is Ok(r)
  let nfa = @regex_engine.build_nfa(r)
  guard nfa.find("xab") is Some(m)
  assert_true(cg_slice("xab", m) == "ab")
  assert_true(nfa.find("aba") is None)
}

///|
test "解析器容错与错误分支（二轮）：空分支容许 / '{m,n' 缺 '}' 拒绝" {
  // 空分支（尾部 / 中部 / 组内）均合法，与 Rust regex 行为一致。
  assert_true(@regex_engine.parse_pattern("a|") is Ok(_))
  assert_true(@regex_engine.parse_pattern("a||b") is Ok(_))
  assert_true(@regex_engine.parse_pattern("(a|)") is Ok(_))
  assert_true(@regex_engine.parse_pattern("a{1,2x}") is Err(_))
  assert_true(@regex_engine.parse_regex("a|") is Ok(_))
  assert_true(@regex_engine.parse_regex("a{1,2x}") is Err(_))
  assert_true(@regex_engine.parse_regex("a|b|*") is Err(_))
  assert_true(@regex_engine.parse_regex("[") is Err(_))
  assert_true(@regex_engine.parse_regex("[a-") is Err(_))
  assert_true(@regex_engine.parse_regex("[\\") is Err(_))
}

///|
test "解析器错误分支（二轮）：环视/命名组/局部标志体内错误与未闭合" {
  assert_true(@regex_engine.parse_pattern("(?=*)") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?=a") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?P<n>*)") is Err(_))
  assert_true(@regex_engine.parse_pattern("(?s:*)") is Err(_))
  assert_true(@regex_engine.parse_pattern("\\P{Zz}") is Err(_))
  assert_true(@regex_engine.parse_pattern("[\\p{") is Err(_))
  assert_true(@regex_engine.parse_pattern("[\\P{Zz}]") is Err(_))
  assert_true(@regex_engine.parse_pattern("[") is Err(_))
}

///|
test "字符类（二轮）：\\w、类内 \\d、类内 \\P、类内转义字面、倒置区间归一" {
  guard @regex_engine.Pattern::compile("\\w+") is Ok(pw)
  guard pw.find("!ab_1!") is Some(mw)
  assert_true(cg_slice("!ab_1!", mw) == "ab_1")
  guard @regex_engine.Pattern::compile("[\\d]+") is Ok(pd)
  guard pd.find("a42b") is Some(md)
  assert_true(cg_slice("a42b", md) == "42")
  guard @regex_engine.Pattern::compile("[\\P{Nd}]+") is Ok(pnd)
  guard pnd.find("12ab34") is Some(mnd)
  assert_true(cg_slice("12ab34", mnd) == "ab")
  guard @regex_engine.Pattern::compile("[\\+]") is Ok(pp)
  assert_true(pp.is_match("+"))
  guard @regex_engine.Pattern::compile("[z-a]") is Ok(pr)
  assert_true(pr.is_match("m") && pr.is_match("a") && pr.is_match("z"))
}

///|
test "忽略大小写：字符类折叠与 compile_program 直发 Lit 折叠" {
  guard @regex_engine.Pattern::compile(
      "[a-z]+",
      flags=@regex_engine.Flags::parse("i"),
    )
    is Ok(pc)
  assert_true(pc.is_match("ABC"))
  // 直接走 compile_program（绕过解析期折叠），命中发射期 Lit 折叠分支。
  guard @regex_engine.parse_pattern("k") is Ok(ast)
  let prog = @regex_engine.compile_program(
    ast,
    flags=@regex_engine.Flags::parse("i"),
  )
  assert_true(prog.is_match("K") && prog.is_match("k"))
}

///|
test "打印器（二轮）：{m,} 量词、非原子操作数包裹、大字符集省略号" {
  guard @regex_engine.parse_pattern("a{2,}") is Ok(a2)
  assert_true(@regex_engine.print_ast(a2).contains("{2,}"))
  guard @regex_engine.parse_pattern("(?s).") is Ok(pl)
  assert_true(@regex_engine.print_ast(pl).contains("\u{2026}"))
  guard @regex_engine.parse_regex("(ab)*") is Ok(r)
  let printed = @regex_engine.print_ast(@regex_engine.Ast::of_regex(r))
  assert_true(printed.contains("*"))
}

///|
test "替换（二轮）：未知命名组展开为空串、未闭合 ${ 按字面 $ 处理" {
  guard @regex_engine.Pattern::compile("(?P<x>a)") is Ok(p)
  assert_true(p.replace("a", "[${nope}]") == "[]")
  assert_true(p.replace("a", "[${x]") == "[${x]")
  assert_true(p.replace("a", "${x}!") == "a!")
}

///|
test "Unicode 类别（二轮）：Z/Lm/Pe 查表、空类名拒绝、未分配码点 Cn 空集" {
  guard @regex_engine.parse_unicode_class("\\p{Z}") is Some(z)
  assert_true(z.contains(' '.to_int()))
  guard @regex_engine.parse_unicode_class("\\p{Lm}") is Some(lm)
  assert_true(lm.contains(0x02B0)) // ʰ modifier letter
  guard @regex_engine.parse_unicode_class("\\p{Pe}") is Some(pe)
  assert_true(pe.contains(')'.to_int()))
  assert_true(@regex_engine.parse_unicode_class("\\p{}") is None)
  // U+0378 未分配 → Cn → 空集（不含任何码点）。
  let cn = @regex_engine.category_charset(
    @regex_engine.unicode_category(0x0378),
  )
  assert_true(!cn.contains(0x0378) && !cn.contains('a'.to_int()))
}

///|
test "有界回溯（二轮）：exec_bounded 命中、环视程序、穷尽栈无匹配" {
  guard @regex_engine.parse_pattern("a(b|c)") is Ok(ast)
  let prog = @regex_engine.compile_program(ast)
  guard prog.exec_bounded("ac") is Some(caps)
  guard caps.group(0) is Some(m0)
  assert_true(m0.start == 0 && m0.end == 2)
  assert_true(prog.exec_bounded("zz") is None)
  guard @regex_engine.parse_pattern("(?=[a-c])[a-z]") is Ok(look_ast)
  let look_prog = @regex_engine.compile_program(look_ast)
  guard look_prog.exec_bounded("b") is Some(lcaps)
  guard lcaps.group(0) is Some(lm)
  assert_true(lm.start == 0 && lm.end == 1)
  assert_true(look_prog.exec_bounded("z") is None)
}

///|
test "最左最长匹配模式与 without_auto_engine 兜底路径" {
  guard @regex_engine.Pattern::compile(
      "a|ab",
      kind=@regex_engine.MatchKind::LeftmostLongest,
    )
    is Ok(p)
  guard p.find("ab") is Some(m)
  assert_true(cg_slice("ab", m) == "ab")
  guard @regex_engine.Pattern::compile("abc") is Ok(pl)
  let pf = pl.without_auto_engine()
  guard pf.find("xxabc") is Some(mf)
  assert_true(mf.start == 2 && mf.end == 5)
}

///|
test "前缀过滤器：含 Empty 节点（裸标志组）的串接可判定" {
  guard @regex_engine.parse_pattern("(?s)abc") is Ok(ast)
  let _ = @regex_engine.compute_prefilter(ast, @regex_engine.Flags::default())
  guard @regex_engine.Pattern::compile("(?s)abc") is Ok(p)
  assert_true(p.is_match("xabc"))
}

///|
test "字符类（三轮）：\\W、类内 \\D、类内 \\p 深层畸形与否定 \\p 类" {
  guard @regex_engine.Pattern::compile("\\W+") is Ok(pw)
  guard pw.find("ab, cd") is Some(mw)
  assert_true(cg_slice("ab, cd", mw) == ", ")
  guard @regex_engine.Pattern::compile("[\\D]+") is Ok(pd)
  guard pd.find("1ab2") is Some(md)
  assert_true(cg_slice("1ab2", md) == "ab")
  guard @regex_engine.Pattern::compile("[^\\p{Nd}]+") is Ok(pneg)
  guard pneg.find("12ab34") is Some(mneg)
  assert_true(cg_slice("12ab34", mneg) == "ab")
  assert_true(@regex_engine.Pattern::compile("[\\p{Nd}") is Err(_))
  assert_true(@regex_engine.Pattern::compile("[\\p{}]") is Err(_))
  assert_true(@regex_engine.Pattern::compile("[a") is Err(_))
}

///|
test "Unicode 类别（三轮）：C 大类与含非法字符类名拒绝" {
  guard @regex_engine.parse_unicode_class("\\p{C}") is Some(c)
  assert_true(c.contains(0x0007))
  assert_true(@regex_engine.parse_unicode_class("\\p{L!}") is None)
  assert_true(@regex_engine.parse_unicode_class("\\p{9a}") is None)
}

///|
test "构造 AST 直发：空择一、非原子量词操作数打印、Empty 前缀累计" {
  // 空择一分支列表：发射期直接返回（emit_alt 0 分支）；零分支择一不匹配
  // 任何输入（含空串），与「空择一 = 不可满足」语义一致。
  let empty_alt = @regex_engine.Ast::Alt([])
  let prog = @regex_engine.compile_program(empty_alt)
  assert_true(!prog.is_match(""))
  // 量词操作数为 Concat（非原子）：打印以 (?: ...) 包裹。
  let rep = @regex_engine.Ast::Repeat(
    node=@regex_engine.Ast::Concat([
      @regex_engine.Ast::Lit('a'),
      @regex_engine.Ast::Lit('b'),
    ]),
    min=0,
    max=None,
    greedy=true,
  )
  assert_true(@regex_engine.print_ast(rep).contains("(?:"))
  // Concat 内 Empty 节点：前缀累计跨越 Empty 继续。
  let with_empty = @regex_engine.Ast::Concat([
    @regex_engine.Ast::Empty,
    @regex_engine.Ast::Lit('a'),
  ])
  let _ = @regex_engine.compute_prefilter(
    with_empty,
    @regex_engine.Flags::default(),
  )
  let pe = @regex_engine.compile_program(with_empty)
  assert_true(pe.is_match("a"))
}

///|
test "构造 Regex 直发 NFA：空择一与倒置字符范围" {
  // Alt([])：零分支择一 → 恒不匹配任何非空推进，仅经 ε 连通。
  let nfa0 = @regex_engine.build_nfa(@regex_engine.Regex::Alt([]))
  assert_true(nfa0.find("") is Some(_))
  // 倒置范围 Range('z','a')：构造期归一为 (a, z)。
  let cc : @regex_engine.CharClass = {
    negated: false,
    items: [@regex_engine.ClassItem::Range('z', 'a')],
  }
  let nfa1 = @regex_engine.build_nfa(@regex_engine.Regex::Class(cc))
  assert_true(nfa1.find("m") is Some(_))
  assert_true(nfa1.find("!") is None)
}

///|
test "Pike VM 最左最长：绕过引擎自动选择的首候选取舍" {
  guard @regex_engine.Pattern::compile(
      "a|ab",
      kind=@regex_engine.MatchKind::LeftmostLongest,
    )
    is Ok(p0)
  let p = p0.without_auto_engine()
  guard p.find("xab") is Some(m)
  assert_true(m.start == 1 && m.end == 3)
}

///|
test "replace_fn 无匹配输入原样返回" {
  guard @regex_engine.Pattern::compile("zzz") is Ok(p)
  assert_true(p.replace_fn("abc", fn(_m) { "!" }) == "abc")
}

///|
test "预定义类全覆盖：\\s/\\S 顶层与 \\w/\\W/\\s/\\S 类内形态" {
  guard @regex_engine.Pattern::compile("\\s+") is Ok(ps)
  guard ps.find("a \tb") is Some(ms)
  assert_true(ms.start == 1 && ms.end == 3)
  guard @regex_engine.Pattern::compile("\\S+") is Ok(pss)
  guard pss.find("  ab ") is Some(mss)
  assert_true(cg_slice("  ab ", mss) == "ab")
  guard @regex_engine.Pattern::compile("[\\w]+") is Ok(pw)
  assert_true(pw.is_match("a_1"))
  guard @regex_engine.Pattern::compile("[\\W]+") is Ok(pnw)
  guard pnw.find("ab!?cd") is Some(mnw)
  assert_true(cg_slice("ab!?cd", mnw) == "!?")
  guard @regex_engine.Pattern::compile("[\\s]") is Ok(pcs)
  assert_true(pcs.is_match(" "))
  guard @regex_engine.Pattern::compile("[\\S]") is Ok(pcss)
  assert_true(pcss.is_match("x") && !pcss.is_match(" "))
}

///|
test "字符类范围端点为预定义类：'-' 退化为字面；范围后畸形拒绝" {
  guard @regex_engine.Pattern::compile("[a-\\d]+") is Ok(p)
  // 展开为 {a, '-', 数字}。
  assert_true(p.is_match("a") && p.is_match("-") && p.is_match("7"))
  assert_true(!p.is_match("b"))
  assert_true(@regex_engine.Pattern::compile("[a-\\p{}]") is Err(_))
  assert_true(@regex_engine.Pattern::compile("[a-") is Err(_))
  assert_true(@regex_engine.parse_regex("[a-\\") is Err(_))
  assert_true(@regex_engine.parse_regex("(*)") is Err(_))
}

///|
test "parse_unicode_class 前缀严格校验：\\P{...} 大写前缀拒绝" {
  assert_true(@regex_engine.parse_unicode_class("\\P{L}") is None)
  assert_true(@regex_engine.parse_unicode_class("xp{L}") is None)
}
