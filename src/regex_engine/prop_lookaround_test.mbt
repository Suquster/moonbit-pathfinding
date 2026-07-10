// prop_lookaround_test.mbt —— 环视差分一致性（INFRA 第五十八批）。
//
// 对任意含环视（前瞻/后顾、正/负）的随机模式与随机输入，Pike VM
// （LeftmostFirst）与有界回溯引擎给出逐组相等的捕获结果；负负对偶
// `(?=x)` 与 `(?!(?!x))` 等价。把第 55/56 批新增的环视执行路径纳入
// 与既有引擎同级的属性测试护航。

///|
/// 随机环视模式生成器：`前缀? 环视 主体` 形态，环视体为 1–2 个
/// 随机小写字母（可带 `+` 量词），四种环视形态等概率。
fn gen_lookaround_pattern(rng : @infra_pbt.Rng) -> String {
  let letters : Array[Char] = ['a', 'b', 'c']
  let pick = fn(r : @infra_pbt.Rng) { "\{letters[r.next_below(3)]}" }
  let body = pick(rng) + (if rng.next_bool() { pick(rng) } else { "" })
  let quant = if rng.next_below(4) == 0 { "+" } else { "" }
  let look = match rng.next_below(4) {
    0 => "(?=" + body + quant + ")"
    1 => "(?!" + body + quant + ")"
    2 => "(?<=" + body + quant + ")"
    _ => "(?<!" + body + quant + ")"
  }
  let prefix = if rng.next_bool() { pick(rng) } else { "" }
  let main_part = pick(rng) +
    (if rng.next_bool() { pick(rng) + "*" } else { "" })
  prefix + look + main_part
}

///|
/// 随机输入：长度 ≤6 的 a–c 串。
fn gen_look_input(rng : @infra_pbt.Rng) -> String {
  let alphabet : Array[Char] = ['a', 'b', 'c']
  let n = rng.next_below(7)
  let mut s = ""
  for _i in 0..<n {
    s = s + "\{alphabet[rng.next_below(3)]}"
  }
  s
}

///|
/// Property：Pike VM 与有界回溯在含环视模式上逐组一致。
test "Feature: regex-engine, Property: lookaround Pike VM vs backtracking agree" {
  let gen : @infra_pbt.Gen[(String, String)] = @infra_pbt.Gen::new(fn(rng) {
    (gen_lookaround_pattern(rng), gen_look_input(rng))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(pair) {
    let (pat, input) = pair
    let prog = match parse_pattern(pat) {
      Ok(a) => compile_program(a)
      Err(_) => return false // 生成器只产出合法模式
    }
    let pike = prog.exec(input, kind=LeftmostFirst)
    match (pike, prog.exec_backtrack(input)) {
      (Some(pc), BtMatch(bc)) => {
        for g in 0..<(pc.group_count() + 1) {
          if pc.group(g) != bc.group(g) {
            return false
          }
        }
        true
      }
      (None, BtNoMatch) => true
      _ => false
    }
  })
  assert_true(ok)
}

///|
/// Property：前瞻负负对偶——`(?=x)` 与 `(?!(?!x))` 在任意输入上等价
/// （嵌套环视是锚定于当前位置的零宽谓词，双重否定消去）。
test "Feature: regex-engine, Property: double-negation lookaround equivalence" {
  let gen : @infra_pbt.Gen[String] = @infra_pbt.Gen::new(gen_look_input)
  let pairs = [
    ("(?=ab)a", "(?!(?!ab))a"),
    ("a(?!b)", "a(?=(?!b))"),
    ("(?=a+b)a*", "(?!(?!a+b))a*"),
  ]
  for pq in pairs {
    let (p1, p2) = pq
    let prog1 = match parse_pattern(p1) {
      Ok(a) => compile_program(a)
      Err(_) => compile_program(Empty)
    }
    let prog2 = match parse_pattern(p2) {
      Ok(a) => compile_program(a)
      Err(_) => compile_program(Empty)
    }
    let ok = @infra_pbt.holds_for_all(gen, fn(s) {
      let m1 = match prog1.exec(s) {
        Some(c) => c.group(0)
        None => None
      }
      let m2 = match prog2.exec(s) {
        Some(c) => c.group(0)
        None => None
      }
      m1 == m2
    })
    assert_true(ok)
  }
}

///|
/// Property：忽略大小写标志下的环视与显式折叠字符类环视等价。
test "Feature: regex-engine, Property: lookaround respects ignore_case folding" {
  let f = Flags::default()
  let fi = { ..f, ignore_case: true }
  let prog_i = match parse_pattern("(?<=a)b", flags=fi) {
    Ok(a) => compile_program(a, flags=fi)
    Err(_) => compile_program(Empty)
  }
  let prog_cls = match parse_pattern("(?<=[aA])[bB]") {
    Ok(a) => compile_program(a)
    Err(_) => compile_program(Empty)
  }
  let gen : @infra_pbt.Gen[String] = @infra_pbt.Gen::new(fn(rng) {
    let alphabet : Array[Char] = ['a', 'A', 'b', 'B']
    let n = rng.next_below(7)
    let mut s = ""
    for _i in 0..<n {
      s = s + "\{alphabet[rng.next_below(4)]}"
    }
    s
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(s) {
    let m1 = match prog_i.exec(s) {
      Some(c) => c.group(0)
      None => None
    }
    let m2 = match prog_cls.exec(s) {
      Some(c) => c.group(0)
      None => None
    }
    m1 == m2
  })
  assert_true(ok)
}
