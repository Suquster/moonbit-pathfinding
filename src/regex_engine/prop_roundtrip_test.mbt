// prop_roundtrip_test.mbt —— 正则语法树往返属性测试（task 6.3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 4：「Regex 语法树往返」——对生成器产出的任一受支持子集内的正则
// 语法树 `r`，对其打印再解析应得到等价语法树（`parse_regex(print_regex(r)) ≡ r`）。
//
//   syntax（Regex 语法树）→ printer（`print_regex`）→ parser（`parse_regex`）
// 二者互为双射（bijection）；本属性即断言该往返对任意合法语法树恒等还原，
// 从而验证打印器与解析器在受支持子集上的互逆性（R2.2 解析 / R2.7 往返）。
//
// 关键：规范化生成（normalized generation）以规避歧义结构
// -----------------------------------------------------------------------
// `print_regex` 与 `parse_regex`（见 printer.mbt / parser.mbt）仅在「规范形态」
// 上互为双射。若随意生成语法树，下列结构会因打印/解析的归一化而破坏往返，
// 故本文件的生成器**刻意只产出规范形态**：
//   1. 量词（`* + ? {m,n}`）的作用对象必须是**原子**（Char / Class / Group）。
//      打印器对非原子作用对象（如 Concat/Alt/嵌套量词）会补上分组 `( )`，
//      重新解析便成了 `Group(...)`，故 `Star(Concat([a,b]))` 不可能往返；
//      正确的可往返形态是 `Star(Group(Concat([a,b])))`。
//   2. `Concat` 至少 2 个元素，且其元素不得再是 `Concat` 或 `Alt`
//      （解析器会扁平化嵌套串接、且择一优先级低于串接，单元素亦被解包）。
//   3. `Alt` 至少 2 个分支，且分支不得再是 `Alt`（解析器扁平化嵌套择一）。
//   4. 复合表达式只能经由 `Group` 进入量词作用域，保证量词绑定范围在重新
//      解析时与原树一致。
// 由此生成的每棵树都落在打印/解析互为双射的规范子集内，使 Property 4 成立。
//
// 字母表与转义：字面字符既取普通字符也取元字符（`( ) * + ? | ^ $ [ ] { } \`），
// 元字符在打印时统一反斜杠转义、解析时还原，从而覆盖转义往返路径；字符类
// 成员覆盖单字符、范围与否定，并包含类内特殊字符（`] - ^ \`）以验证类内转义。
//
// 往返断言同时以两种 @infra_pbt 模板表达，二者都校验 Property 4：
//   * `@infra_pbt.round_trip`   —— 经 `Bytes` 编解码桥接的往返模板（≥100 迭代）；
//   * `@infra_pbt.holds_for_all` —— 直接以 `parse(print(r)) == Ok(r)` 谓词的
//     不变量模板（默认 `iters=100`）。
// 生成器复用 @infra_pbt 的种子驱动随机源 `Rng`，保证三后端逐位一致与可重放。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。
//
// 说明：本文件的生成器 / 桥接辅助统一以 `rt_` / `gen_rt_` 前缀命名，与同包内
// 其它属性测试文件（prop_nfa_dfa_test.mbt 的 `gen_class` / `gen_regex_at` 等）
// 的符号互不冲突。

// ---------------------------------------------------------------------------
// 字面字符生成（generator）—— 覆盖普通字符与需转义的元字符
// ---------------------------------------------------------------------------

///|
/// 生成一个字面字符：约 1/4 概率取正则元字符（打印时反斜杠转义、解析时还原），
/// 其余取普通字面字符。所有字符均为 ASCII（码位 < 128），便于经 `Bytes` 无损往返。
fn gen_rt_char(rng : @infra_pbt.Rng) -> Char {
  let literals : Array[Char] = [
    'a', 'b', 'c', 'd', 'x', 'y', '0', '1', '2', '.', '_',
  ]
  let metas : Array[Char] = [
    '(', ')', '*', '+', '?', '|', '^', '$', '[', ']', '{', '}', '\\',
  ]
  if rng.next_below(4) == 0 {
    metas[rng.next_below(metas.length())]
  } else {
    literals[rng.next_below(literals.length())]
  }
}

// ---------------------------------------------------------------------------
// 字符类生成（generator）—— 单字符 / 范围 / 否定，含类内转义字符
// ---------------------------------------------------------------------------

///|
/// 随机字符类生成器：1~3 个成员项，随机决定是否否定。
///
/// 单字符成员取自含类内特殊字符（`] - ^ \`）的小集合，以验证类内转义往返；
/// 范围成员取自连续小字母表并保证 `lo <= hi`。打印器对类内特殊字符转义、
/// 解析器对应还原，故任一形态都落在可往返的规范子集内。
fn gen_rt_class(rng : @infra_pbt.Rng) -> Regex {
  let singles : Array[Char] = [
    'a', 'b', 'c', '0', '1', ']', '-', '^', '\\', 'x',
  ]
  let negated = rng.next_bool()
  let count = rng.next_range(1, 3)
  let items : Array[ClassItem] = []
  for _i in 0..<count {
    if rng.next_bool() {
      // 范围成员 lo-hi（含两端）：取自连续小字母表，保证 lo <= hi。
      let base : Array[Char] = if rng.next_bool() {
        ['a', 'b', 'c', 'd', 'e', 'f']
      } else {
        ['0', '1', '2', '3', '4']
      }
      let i = rng.next_below(base.length())
      let j = rng.next_below(base.length())
      let lo = if i <= j { base[i] } else { base[j] }
      let hi = if i <= j { base[j] } else { base[i] }
      items.push(Range(lo, hi))
    } else {
      // 单字符成员（含类内特殊字符，验证类内转义）。
      items.push(Single(singles[rng.next_below(singles.length())]))
    }
  }
  Class({ negated, items })
}

// ---------------------------------------------------------------------------
// 规范语法树生成（generator）—— 仅产出打印/解析互为双射的形态
// ---------------------------------------------------------------------------

///|
/// 量词作用对象生成器：仅产出**原子**（Char / Class / Group）。
///
/// 量词只能作用于原子才能往返：打印器对非原子作用对象会补分组，重新解析
/// 即变为 `Group`。复合表达式通过 `Group(gen_rt_expr(depth-1))` 进入，保证
/// 量词绑定范围在解析时一致。深度耗尽时退化为 Char / Class 叶子。
fn gen_rt_quant_operand(rng : @infra_pbt.Rng, depth : Int) -> Regex {
  if depth <= 0 {
    if rng.next_bool() {
      Char(gen_rt_char(rng))
    } else {
      gen_rt_class(rng)
    }
  } else {
    match rng.next_below(3) {
      0 => Char(gen_rt_char(rng))
      1 => gen_rt_class(rng)
      _ => Group(gen_rt_expr(rng, depth - 1))
    }
  }
}

///|
/// 「可量词化单元」生成器：先取一个原子作用对象，再以一定概率附加量词。
///
/// 量词覆盖打印器的全部后缀分支：`*` / `+` / `?` / `{m}`（上下界相等）/
/// `{m,}`（无上界）/ `{m,n}`（`n > m`）；亦可不加量词直接返回原子。
fn gen_rt_quantifiable(rng : @infra_pbt.Rng, depth : Int) -> Regex {
  let operand = gen_rt_quant_operand(rng, depth)
  match rng.next_below(7) {
    0 => Star(operand)
    1 => Plus(operand)
    2 => Opt(operand)
    // {m}：上下界相等，打印为 `{m}`。
    3 => {
      let m = rng.next_range(0, 4)
      Repeat(operand, m, Some(m))
    }
    // {m,}：无上界。
    4 => {
      let m = rng.next_range(0, 4)
      Repeat(operand, m, None)
    }
    // {m,n}：n > m，打印为 `{m,n}`。
    5 => {
      let m = rng.next_range(0, 3)
      let extra = rng.next_range(1, 3)
      Repeat(operand, m, Some(m + extra))
    }
    _ => operand
  }
}

///|
/// 串接元素生成器：要么是锚点（`^` / `$`），要么是可量词化单元。
///
/// 串接元素本身必须是「串接安全」的——不得是 `Concat` 或 `Alt`，否则解析器
/// 的扁平化 / 优先级会改变结构。锚点与可量词化单元均满足该约束。
fn gen_rt_concat_part(rng : @infra_pbt.Rng, depth : Int) -> Regex {
  if rng.next_below(6) == 0 {
    Anchor(if rng.next_bool() { Start } else { End })
  } else {
    gen_rt_quantifiable(rng, depth)
  }
}

///|
/// 串接生成器：1 个元素时直接返回该元素（避免单元素 `Concat` 被解析器解包
/// 而破坏往返）；2~3 个元素时包成 `Concat`。元素均为串接安全形态。
fn gen_rt_concat(rng : @infra_pbt.Rng, depth : Int) -> Regex {
  let n = rng.next_range(1, 3)
  if n == 1 {
    gen_rt_concat_part(rng, depth)
  } else {
    let parts : Array[Regex] = []
    for _i in 0..<n {
      parts.push(gen_rt_concat_part(rng, depth))
    }
    Concat(parts)
  }
}

///|
/// 顶层表达式生成器：约 1/4 概率产出 `Alt`（≥2 个分支，分支为串接，绝不再是
/// `Alt`，规避嵌套择一扁平化），否则产出一个串接。深度耗尽时退化为叶子。
fn gen_rt_expr(rng : @infra_pbt.Rng, depth : Int) -> Regex {
  if depth <= 0 {
    if rng.next_bool() {
      Char(gen_rt_char(rng))
    } else {
      gen_rt_class(rng)
    }
  } else if rng.next_below(4) == 0 {
    let k = rng.next_range(2, 3)
    let branches : Array[Regex] = []
    for _i in 0..<k {
      branches.push(gen_rt_concat(rng, depth - 1))
    }
    Alt(branches)
  } else {
    gen_rt_concat(rng, depth)
  }
}

///|
/// 规范正则语法树生成器：深度上限 4，保证树规模有界且覆盖各类节点形态。
fn gen_roundtrip_regex() -> @infra_pbt.Gen[Regex] {
  @infra_pbt.Gen::new(fn(rng) { gen_rt_expr(rng, 4) })
}

// ---------------------------------------------------------------------------
// Bytes 编解码桥接（供 round_trip 模板使用）
// ---------------------------------------------------------------------------

///|
/// 编码：语法树 -> 打印文本 -> `Bytes`（逐字符取 ASCII 码）。
///
/// 打印结果仅含 ASCII 字符（码位 < 128，含转义反斜杠），故 `to_byte` 无损。
fn rt_regex_to_bytes(r : Regex) -> Bytes {
  let s = print_regex(r)
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 解码：`Bytes` -> 文本（逐字节还原 ASCII 字符）-> 解析为语法树。
///
/// 与 `rt_regex_to_bytes` 互逆；解析失败时返回 `None`（往返失败）。
fn rt_bytes_to_regex(b : Bytes) -> Regex? {
  let mut s = ""
  let mut i = 0
  while i < b.length() {
    let c = b[i].to_int().unsafe_to_char()
    s = s + "\{c}"
    i = i + 1
  }
  match parse_regex(s) {
    Ok(r) => Some(r)
    Err(_) => None
  }
}

// ---------------------------------------------------------------------------
// 单元测试（具体见证）—— 锁定规范形态在代表性语法树上的往返
// ---------------------------------------------------------------------------

///|
/// 对一组代表性规范语法树，`parse_regex(print_regex(r))` 应得到等价语法树
/// （Property 4 的具体见证；属性形式见下方 round_trip / holds_for_all 测试）。
test "round-trip holds on representative canonical syntax trees" {
  let samples : Array[Regex] = [
    // 量词只作用于原子（Char / Class / Group）。
    Star(Char('a')),
    Plus(Char('+')), // 元字符字面 '+' 经转义往返。
    Opt(Class({ negated: false, items: [Range('a', 'z'), Single('_')] })),
    Repeat(Char('a'), 2, Some(2)), // {2}
    Repeat(Char('a'), 1, None), // {1,}
    Repeat(Char('b'), 2, Some(5)), // {2,5}
    // 复合表达式经 Group 进入量词作用域。
    Star(Group(Concat([Char('a'), Char('b')]))),
    Plus(Group(Alt([Char('a'), Char('b')]))),
    // 串接（≥2 元素，元素为串接安全形态），含锚点。
    Concat([Anchor(Start), Char('x'), Star(Char('y')), Anchor(End)]),
    // 择一（≥2 分支，分支为串接）。
    Alt([Concat([Char('a'), Char('b')]), Char('c')]),
    // 含否定字符类与类内特殊字符转义。
    Class({ negated: true, items: [Range('0', '9'), Single(']'), Single('-')] }),
  ]
  for r in samples {
    assert_true(parse_regex(print_regex(r)) == Ok(r))
  }
}

// ---------------------------------------------------------------------------
// Property 4：Regex 语法树往返
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 4: Regex 语法树往返（round_trip 模板）
///
/// 对任意由生成器产出的规范正则语法树 `r`，经"打印 → Bytes → 解析"的往返
/// 应还原为等价语法树（`parse_regex(print_regex(r)) ≡ r`）。复用 @infra_pbt
/// 的 `round_trip` 往返断言模板，默认迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 2.2, 2.7**
test "Feature: moonbit-infra-suite, Property 4: parse(print(r)) round-trips (round_trip template)" {
  let ok = @infra_pbt.round_trip(
    gen_roundtrip_regex(),
    rt_regex_to_bytes,
    rt_bytes_to_regex,
  )
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 4: Regex 语法树往返（holds_for_all 模板）
///
/// 同一往返性质的直接谓词形式：对任意生成的语法树 `r`，
/// `parse_regex(print_regex(r))` 应恰好等于 `Ok(r)`。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 2.2, 2.7**
test "Feature: moonbit-infra-suite, Property 4: parse(print(r)) equals r (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(gen_roundtrip_regex(), fn(r) {
    parse_regex(print_regex(r)) == Ok(r)
  })
  assert_true(ok)
}
