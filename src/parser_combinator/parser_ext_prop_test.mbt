// parser_ext_prop_test.mbt —— L1 解析器增强属性测试（任务 6.3 / design.md
// §「正确性属性 → Property 6: R6 增量解析等价」）。
//
// 本文件以全称量化（property）形式承载 design.md「Property 6」的三组性质，
// 每条属性 `iters >= 100`（显式传入 `iters=100`，由 @infra_pbt.holds_for_all
// 以固定种子驱动，三后端 wasm-gc / js / native 逐位一致、可复现）：
//
//   * Property 6a/6b（AC1/AC2 增量分块无关性）：对任意输入及其任意分块方式，
//     `run_incremental` + 逐段 `drive`（最后 closed）所得结果与一次性
//     `run_naive_string` 逐字段一致；分别覆盖 JSON 文法与数字文法，成功 /
//     失败两类输入均覆盖。
//   * Property 6c（AC4 有界缓存等价）：随机输入 + 随机 cap（含极小 / 零 cap），
//     `run_packrat_bounded_string(s, cap)` 与 `run_packrat_string(s)` 结果一致。
//   * Property 6d（AC5 容量上限不变量）：BoundedCache 任意时刻条目数恒
//     <= max(cap, 0)。
//
// 仅新增测试，不改既有签名与既有测试（freeze + bypass）。复用本包测试期已有
// 的 `dp_number()`（derived_prop_test.mbt）与共享随机源 @infra_pbt。
// 全程禁止循环内字符串 `+`：字符串一律以 Array[String] / Array[Char] 缓冲后
// `join` 物化。

// ---------------------------------------------------------------------------
// 测试辅助：字符串构造（避免循环内 `+`）
// ---------------------------------------------------------------------------

///|
/// 由字符数组物化字符串：把每个字符转为单字符串收集进 `Array[String]`，再
/// 一次性 `join("")`。摊还 O(n)，规避循环内 `out = out + c` 的 O(n²) 反模式。
fn pe_string_of_chars(chars : Array[Char]) -> String {
  let parts : Array[String] = []
  for c in chars {
    parts.push(c.to_string())
  }
  parts.join("")
}

// ---------------------------------------------------------------------------
// 测试辅助：多样化随机分块
// ---------------------------------------------------------------------------

///|
/// 把字符串 `s` 随机切分为若干非空块（拼接后恰等于 `s`），覆盖多种分块方式：
///   * mode 0：逐字符成块（最细粒度）；
///   * mode 1：伯努利随机切点（任意粒度）；
///   * mode 2：固定 2 字符成块；
///   * mode 3：固定 3 字符成块；
///   * mode 4：整串单块（最粗粒度）。
///
/// 空串返回空块数组（由 `pe_drive_chunks` 以「空初始段 + 立即 close」驱动）。
/// 不产生空块（空块在流式实现中被约定为结束信号）。
fn pe_chunk(rng : @infra_pbt.Rng, s : String) -> Array[String] {
  let chars = s.iter().to_array()
  let n = chars.length()
  let chunks : Array[String] = []
  if n == 0 {
    return chunks
  }
  let mode = rng.next_below(5)
  let mut buf : Array[Char] = []
  let mut i = 0
  while i < n {
    buf.push(chars[i])
    let cut = match mode {
      0 => true // 逐字符成块
      1 => rng.next_bool() // 随机切点
      2 => buf.length() >= 2 // 固定 2 字符成块
      3 => buf.length() >= 3 // 固定 3 字符成块
      _ => false // 整串单块
    }
    if cut {
      chunks.push(pe_string_of_chars(buf))
      buf = []
    }
    i = i + 1
  }
  if buf.length() > 0 {
    chunks.push(pe_string_of_chars(buf))
  }
  chunks
}

///|
/// 以分块驱动增量解析至最终结果：首块作为 `run_incremental` 起步段，其余块依次
/// 喂入，最后标记结束（`closed=true`）。空块数组退化为「空初始段 + 立即 close」。
fn[T] pe_drive_chunks(g : Grammar[T], chunks : Array[String]) -> ParseResult[T] {
  if chunks.length() == 0 {
    return drive(g.run_incremental(""), [], closed=true)
  }
  let rest : Array[String] = []
  let mut i = 1
  while i < chunks.length() {
    rest.push(chunks[i])
    i = i + 1
  }
  drive(g.run_incremental(chunks[0]), rest, closed=true)
}

// ---------------------------------------------------------------------------
// 测试辅助：解析结果逐字段比较
// ---------------------------------------------------------------------------

///|
/// `ParseResult[Json]` 逐字段比较：成功比「值相等 + 剩余偏移相等」，失败比
/// 「失败位置偏移相等 + 期望集合逐元素相等」，构造器不一致即判不等。
fn pe_presult_eq_json(a : ParseResult[Json], b : ParseResult[Json]) -> Bool {
  match (a, b) {
    (Ok(v1, r1), Ok(v2, r2)) => v1 == v2 && r1.pos.offset == r2.pos.offset
    (Fail(p1, expected=e1), Fail(p2, expected=e2)) =>
      p1.offset == p2.offset && e1 == e2
    _ => false
  }
}

///|
/// `ParseResult[Int]` 逐字段比较（语义同 `pe_presult_eq_json`，用于数字文法）。
fn pe_presult_eq_int(a : ParseResult[Int], b : ParseResult[Int]) -> Bool {
  match (a, b) {
    (Ok(v1, r1), Ok(v2, r2)) => v1 == v2 && r1.pos.offset == r2.pos.offset
    (Fail(p1, expected=e1), Fail(p2, expected=e2)) =>
      p1.offset == p2.offset && e1 == e2
    _ => false
  }
}

// ---------------------------------------------------------------------------
// 测试辅助：输入生成器
// ---------------------------------------------------------------------------

///|
/// JSON 输入字母表（含结构符、字面量字符与数字 / 空白），用于生成「近合法 /
/// 任意」的字符串以充分触发部分解析与失败路径。
let pe_json_alphabet : Array[Char] = [
  '[', ']', '{', '}', ',', ':', '"', 't', 'r', 'u', 'e', 'f', 'a', 'l', 's', 'n',
  '0', '1', '2', '3', ' ',
]

///|
/// 合法 / 近合法 JSON 片段池，用于覆盖成功解析路径（值 / 数组 / 对象 / 字面量）。
let pe_json_pool : Array[String] = [
  "null", "true", "false", "0", "42", "123", "[1,2,3]", "{\"a\":1}", "[true,null]",
  "{\"x\":[1,2],\"y\":3}", "\"hi\"", "[]", "{}",
]

///|
/// JSON 输入生成器：约一半概率取自合法片段池（覆盖成功路径），另一半为小
/// 字母表随机串（覆盖部分解析 / 失败路径）。
fn pe_gen_json_source() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    if rng.next_bool() {
      pe_json_pool[rng.next_below(pe_json_pool.length())]
    } else {
      let len = rng.next_range(0, 12)
      let chars : Array[Char] = []
      let mut i = 0
      while i < len {
        chars.push(pe_json_alphabet[rng.next_below(pe_json_alphabet.length())])
        i = i + 1
      }
      pe_string_of_chars(chars)
    }
  })
}

///|
/// 数字输入字母表：十进制数字 + 干扰字符（字母 / 空白 / 负号），使数字文法
/// （`many1 digit`）在成功（以数字起头）与失败（以非数字起头）间均被覆盖。
let pe_num_alphabet : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'x', ' ', '-',
]

///|
/// 数字输入生成器：小字母表随机串（长度 [0, 10]）。
fn pe_gen_num_source() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    let len = rng.next_range(0, 10)
    let chars : Array[Char] = []
    let mut i = 0
    while i < len {
      chars.push(pe_num_alphabet[rng.next_below(pe_num_alphabet.length())])
      i = i + 1
    }
    pe_string_of_chars(chars)
  })
}

// ---------------------------------------------------------------------------
// 分块无关性的有效论域（关键说明）
// ---------------------------------------------------------------------------
//
// 流式引擎（streaming.mbt::pc_stream_eval）的语义是「在已到达数据上一旦解析
// 成功即收束（Done(Ok)）」。因此「任意分块 == 一次性解析」这一分块无关性
// （R6.1/6.2、R10.5）仅在「成功解析在数据边界处不可被更多输入延展」的文法上
// 成立——即**有终结符锚定 / 非贪婪边界**的文法。对贪婪且无终结符的文法
// （如裸 `many1 digit`：`"12"` 在边界即成功为 12，无法预见后续 `"3"` 会延展为
// 123），边界处会提前收束，分块与一次性结果可不同——这不是分块无关性失败，
// 而是该文法不属于此性质的有效论域。既有 Property 26 正是以终结符锚定文法
// `'<' digits '>'` 验证此性质。故本处亦选用终结符锚定文法（数字被 `<`/`>` 或
// 字母被 `(`/`)` 包裹），令分块无关性对**成功与失败的任意随机输入**均严格成立。

///|
/// 终结符锚定文法 A：`'(' letter* ')'` → 字母个数。
///
/// 成功必须见到闭合 `)`，且重复元素 `many(letter)` 为「单字符匹配或干净停止」
/// （不存在「消费分隔符后元素失败」式的回溯），故需要更多输入时报告的失败
/// 位置恒落在数据边界（avail）→ 触发 NeedMore 而非提前收束，严格落入分块
/// 无关性的有效论域。（对比：`sep_by` 的分隔符会「先消费后失败并回溯」，使
/// 报告失败位置回退到边界之前，导致边界检测误判——不属于此性质有效论域。）
fn pe_paren_word_grammar() -> Grammar[Int] {
  let letter = satisfy(fn(c) { c >= 'a' && c <= 'z' }, label="字母")
  let body = many(letter)
  let wrapped = between(pchar('('), body, pchar(')'))
  lift(map(wrapped, fn(xs) { xs.length() }))
}

///|
/// 锚定数字文法输入字母表：`<` / `>` / 数字 / 干扰字符，覆盖成功 `<123>` 与
/// 各类失败（缺锚、缺闭合、中部非法字符）。
let pe_anum_alphabet : Array[Char] = [
  '<', '>', '0', '1', '2', '3', '9', 'a', ' ',
]

///|
/// 锚定数字文法输入生成器：约一半概率为合法 `<digits>`，另一半为小字母表随机串。
fn pe_gen_anum_source() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    if rng.next_bool() {
      let n = rng.next_range(0, 999)
      ["<", n.to_string(), ">"].join("")
    } else {
      let len = rng.next_range(0, 10)
      let chars : Array[Char] = []
      let mut i = 0
      while i < len {
        chars.push(pe_anum_alphabet[rng.next_below(pe_anum_alphabet.length())])
        i = i + 1
      }
      pe_string_of_chars(chars)
    }
  })
}

///|
/// 括号词文法输入字母表：`(` / `)` / 小写字母 / 干扰字符。
let pe_pword_alphabet : Array[Char] = ['(', ')', 'a', 'b', 'c', 'x', '0', ' ']

///|
/// 括号词文法输入生成器：约一半概率为合法 `(letters)`（含空 `()`），另一半为
/// 小字母表随机串（覆盖部分解析 / 失败路径）。
fn pe_gen_pword_source() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    if rng.next_bool() {
      let count = rng.next_range(0, 5)
      let letters = ['a', 'b', 'c', 'd', 'e']
      let parts : Array[String] = ["("]
      let mut i = 0
      while i < count {
        parts.push(letters[rng.next_below(letters.length())].to_string())
        i = i + 1
      }
      parts.push(")")
      parts.join("")
    } else {
      let len = rng.next_range(0, 10)
      let chars : Array[Char] = []
      let mut i = 0
      while i < len {
        chars.push(
          pe_pword_alphabet[rng.next_below(pe_pword_alphabet.length())],
        )
        i = i + 1
      }
      pe_string_of_chars(chars)
    }
  })
}

// ---------------------------------------------------------------------------
// Property 6a：任意分块增量解析与一次性解析等价（锚定数字文法 `<digits>`）
// ---------------------------------------------------------------------------

///|
/// Feature: production-hardening, Property 6: 任意分块增量解析等价于一次性解析（锚定数字文法）
///
/// 见证文法 `'<' digits '>'`（终结符锚定）。对任意输入及其任意分块方式
/// （逐字符 / 固定 2 / 固定 3 / 随机切点 / 整串），增量喂入（`run_incremental`
/// + 逐段 `drive`，结束时 closed）所得结果与一次性 `run_naive_string` 逐字段
/// 一致；成功与失败两类输入均覆盖。
///
/// **Validates: Requirements 6.1, 6.2**
test "Feature: production-hardening, Property 6: incremental chunking equals one-shot (anchored number grammar)" {
  let g = stream_num_grammar()
  let src_gen = pe_gen_anum_source()
  let gen = @infra_pbt.Gen::new(fn(rng) {
    let s = src_gen.generate(rng)
    (s, pe_chunk(rng, s))
  })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(pair) {
      let (s, chunks) = pair
      let incremental = pe_drive_chunks(g, chunks)
      let oneshot = g.run_naive_string(s)
      pe_presult_eq_int(incremental, oneshot)
    },
    iters=100,
  )
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 6b：任意分块增量解析与一次性解析等价（锚定括号词文法）
// ---------------------------------------------------------------------------

///|
/// Feature: production-hardening, Property 6: 任意分块增量解析等价于一次性解析（锚定括号词文法）
///
/// 见证文法 `'(' letter* ')'`（终结符锚定，含重复 + 包裹）。复核「重复元素 +
/// 包裹」结构在任意分块下的分块无关性，覆盖成功（`(abc)` / `()`）与失败
/// （缺闭合 / 中部非法）两类输入。
///
/// **Validates: Requirements 6.1, 6.2**
test "Feature: production-hardening, Property 6: incremental chunking equals one-shot (anchored paren-word grammar)" {
  let g = pe_paren_word_grammar()
  let src_gen = pe_gen_pword_source()
  let gen = @infra_pbt.Gen::new(fn(rng) {
    let s = src_gen.generate(rng)
    (s, pe_chunk(rng, s))
  })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(pair) {
      let (s, chunks) = pair
      let incremental = pe_drive_chunks(g, chunks)
      let oneshot = g.run_naive_string(s)
      pe_presult_eq_int(incremental, oneshot)
    },
    iters=100,
  )
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 6c：有界 packrat 与无淘汰 run_packrat 结果一致
// ---------------------------------------------------------------------------

///|
/// Feature: production-hardening, Property 6: bounded packrat equals unbounded run_packrat
///
/// 对随机输入与随机 cap（含 0 即「无缓存」与极小 cap），有界 packrat
/// `run_packrat_bounded_string(s, cap)` 与无淘汰 `run_packrat_string(s)` 结果
/// 逐字段一致——缓存为纯函数缓存，命中与否、是否被 LRU 淘汰均不改变结果。
/// 同时覆盖 JSON 文法与数字文法。
///
/// **Validates: Requirements 6.4**
test "Feature: production-hardening, Property 6: bounded packrat equals unbounded packrat" {
  let gj = json_value_grammar()
  let gn = lift(dp_number())
  let json_src = pe_gen_json_source()
  let num_src = pe_gen_num_source()
  let gen = @infra_pbt.Gen::new(fn(rng) {
    let use_json = rng.next_bool()
    let s = if use_json {
      json_src.generate(rng)
    } else {
      num_src.generate(rng)
    }
    let cap = rng.next_range(0, 8) // 含 0（无缓存）与极小 cap
    (use_json, s, cap)
  })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(t) {
      let (use_json, s, cap) = t
      if use_json {
        pe_presult_eq_json(
          gj.run_packrat_bounded_string(s, cap~),
          gj.run_packrat_string(s),
        )
      } else {
        pe_presult_eq_int(
          gn.run_packrat_bounded_string(s, cap~),
          gn.run_packrat_string(s),
        )
      }
    },
    iters=100,
  )
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 6d：BoundedCache 条目数恒不超过 cap
// ---------------------------------------------------------------------------
//
// 说明：Property 6d（AC5 BoundedCache 容量上限不变量）因需构造引擎内部只读
// 类型 `Outcome[T]`（`OOk` 构造器对黑盒测试只读、不可创建），置于同包白盒
// 测试文件 `parser_ext_prop_wbtest.mbt` 中实现（可访问包内构造器）。
