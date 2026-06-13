// prop_captures_test.mbt —— Property 3：捕获正确性（任务 6.2）。
//
// Feature: regex-engine, Property 3: 捕获正确性
//
// 对任意含捕获 / 命名 / 非捕获组的模式与任意能成功匹配的输入：第 0 组等于
// 整体匹配区间；每个已设置的第 `g` 组区间都是第 0 组的子区间；非捕获组不占
// 编号（编号严格按左括号源顺序，故 `group_count() == 捕获组数 + 1`）；命名组
// 经 `Captures::name` 检索得到与其编号 `Captures::group` 一致的结果；未参与
// 匹配的组返回未设置（`None`）而非导致整体失败。
//
// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.4, 8.4, 11.2**
//
// 复用 @infra_pbt 种子驱动随机源（≥100 迭代，holds_for_all 默认 iters=100）。
// 生成器产出**结构已知**的模式（同时记录捕获组数与命名组编号映射），使「编号
// 严格按源顺序」「命名 == 编号」等不变量可被精确校验。

///|
/// 捕获模式规格：模式串 + 捕获组总数（不含第 0 组）+ 命名组「名称 → 编号」。
priv struct CapSpec {
  pattern : String
  total : Int
  names : Array[(String, Int)]
}

///|
/// 模式字母表（与输入字母表交叠，保证匹配频繁发生）。
fn cap_atom(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(5) {
    0 => "a"
    1 => "b"
    2 => "c"
    3 => "[abc]"
    _ => "[a-c]"
  }
}

///|
/// 组体：1~2 个无组原子串接（不含子组，保证编号仅由顶层左括号顺序决定）。
fn cap_body(rng : @infra_pbt.Rng) -> String {
  let n = rng.next_range(1, 2)
  let mut s = ""
  for _i in 0..<n {
    s = s + cap_atom(rng)
  }
  s
}

///|
/// 可选量词后缀：空 / `*` / `+` / `?`（`*` `?` 可使组未参与，覆盖 R1.5）。
fn cap_quant(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(4) {
    0 => ""
    1 => "*"
    2 => "+"
    _ => "?"
  }
}

///|
/// 生成结构已知的捕获模式：1~4 个段，段为字面 / 捕获组 / 命名组 / 非捕获组。
fn gen_capture_spec(rng : @infra_pbt.Rng) -> CapSpec {
  let mut next_group = 1
  let names : Array[(String, Int)] = []
  let mut pat = ""
  let seg_count = rng.next_range(1, 4)
  for _i in 0..<seg_count {
    match rng.next_below(5) {
      // 捕获组。
      1 => {
        let _idx = next_group
        next_group = next_group + 1
        pat = pat + "(" + cap_body(rng) + ")" + cap_quant(rng)
      }
      // 命名捕获组（名称按编号唯一，绝不重名）。
      2 => {
        let idx = next_group
        next_group = next_group + 1
        let nm = "g" + idx.to_string()
        names.push((nm, idx))
        pat = pat + "(?<" + nm + ">" + cap_body(rng) + ")" + cap_quant(rng)
      }
      // 非捕获组（不占编号）。
      3 => pat = pat + "(?:" + cap_body(rng) + ")" + cap_quant(rng)
      // 字面字符（无组）。
      _ => pat = pat + cap_atom(rng)
    }
  }
  { pattern: pat, total: next_group - 1, names }
}

///|
/// 输入生成器：字符取自 {a,b,c}，长度 0~`max_len`。
fn cap_input(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let alphabet : Array[Char] = ['a', 'b', 'c']
  let len = rng.next_below(max_len + 1)
  let mut s = ""
  for _i in 0..<len {
    s = s + alphabet[rng.next_below(alphabet.length())].to_string()
  }
  s
}

///|
/// 联合生成器：`(捕获模式规格, 随机输入)`。
fn gen_cap_case() -> @infra_pbt.Gen[(CapSpec, String)] {
  @infra_pbt.Gen::new(fn(rng) {
    let spec = gen_capture_spec(rng)
    let input = cap_input(rng, 6)
    (spec, input)
  })
}

///|
/// 校验一次成功匹配的捕获结果满足全部捕获不变量。
fn cap_check(caps : Captures, spec : CapSpec) -> Bool {
  // 非捕获组不占号：组总数（含第 0 组）= 捕获组数 + 1。
  if caps.group_count() != spec.total + 1 {
    return false
  }
  // 第 0 组（整体匹配）必存在。
  let g0 = match caps.group(0) {
    Some(m) => m
    None => return false
  }
  // 命名检索与编号检索一致。
  for pair in spec.names {
    let (nm, idx) = pair
    if caps.name(nm) != caps.group(idx) {
      return false
    }
  }
  // 每个已设置的第 g 组都是第 0 组的子区间且区间合法。
  let mut g = 1
  while g <= spec.total {
    match caps.group(g) {
      Some(m) =>
        if not(m.start >= g0.start && m.end <= g0.end && m.start <= m.end) {
          return false
        }
      None => () // 未参与匹配 → 未设置（合法，R1.5）。
    }
    g = g + 1
  }
  true
}

///|
/// 健全性：生成器只产出可成功编译的模式（避免主属性被平凡满足）。
test "Feature: regex-engine, Property 3: capture spec generator only emits valid patterns" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) { gen_capture_spec(rng) }),
    fn(spec) {
      match Pattern::compile(spec.pattern) {
        Ok(_) => true
        Err(_) => false
      }
    },
  )
  assert_true(ok)
}

///|
/// Feature: regex-engine, Property 3: 捕获正确性
///
/// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.4, 8.4, 11.2**
test "Feature: regex-engine, Property 3: capture correctness" {
  let ok = @infra_pbt.holds_for_all(gen_cap_case(), fn(pair) {
    let (spec, input) = pair
    match Pattern::compile(spec.pattern) {
      Err(_) => false
      Ok(pat) =>
        match pat.captures(input) {
          None => true // 无匹配 → 性质平凡成立。
          Some(caps) => cap_check(caps, spec)
        }
    }
  })
  assert_true(ok)
}

///|
/// 代表性见证：非捕获组不占号、编号按源顺序、命名 == 编号、未设置组为 None。
test "capture correctness representative witnesses" {
  // (a)(?:b)(c) on "abc"：非捕获组穿插，捕获组编号为 1、2。
  match Pattern::compile("(a)(?:b)(c)") {
    Ok(p) =>
      match p.captures("abc") {
        Some(c) => {
          assert_true(c.group(0) == Some({ start: 0, end: 3 }))
          assert_true(c.group(1) == Some({ start: 0, end: 1 }))
          assert_true(c.group(2) == Some({ start: 2, end: 3 }))
          assert_eq(c.group_count(), 3)
        }
        None => fail("expected match for (a)(?:b)(c)")
      }
    Err(_) => fail("compile failed for (a)(?:b)(c)")
  }
  // 命名组：按名检索与编号检索一致。
  match Pattern::compile("(?<x>a)(?<y>b)") {
    Ok(p) =>
      match p.captures("ab") {
        Some(c) => {
          assert_true(c.name("x") == c.group(1))
          assert_true(c.name("y") == c.group(2))
          assert_true(c.name("x") == Some({ start: 0, end: 1 }))
        }
        None => fail("expected match for named groups")
      }
    Err(_) => fail("compile failed for named groups")
  }
  // 未走通分支的组返回 None，而非整体失败。
  match Pattern::compile("(a)|(b)") {
    Ok(p) =>
      match p.captures("b") {
        Some(c) => {
          assert_true(c.group(0) == Some({ start: 0, end: 1 }))
          assert_true(c.group(1) == None)
          assert_true(c.group(2) == Some({ start: 0, end: 1 }))
        }
        None => fail("expected match for alternation")
      }
    Err(_) => fail("compile failed for alternation")
  }
}
