// demo_test.mbt —— 实战 demo 正则集单元测试（任务 10.2）。
//
// 对应 design.md §4.11（R11）。对每个 demo 模式与样例输入校验整体匹配区间、
// 各捕获组区间（编号 / 命名），以及 `replace_all` 引用捕获组的预期重写结果。
//
// _Requirements: 11.2, 11.3_

///|
/// 取输入在匹配区间 `[m.start, m.end)` 上的子串切片。
fn dt_slice(input : String, m : Match) -> String {
  let chars = input.iter().to_array()
  let mut s = ""
  for k in m.start..<m.end {
    s = s + chars[k].to_string()
  }
  s
}

///|
/// 健全性：全部 demo 模式都能成功编译为 `Pattern`。
test "demo all patterns compile" {
  for case in demo_cases() {
    let (pat, _input) = case
    match Pattern::compile(pat) {
      Ok(_) => ()
      Err(_) => fail("demo pattern failed to compile: " + pat)
    }
  }
}

///|
/// 健全性：每个 demo 模式在其样例输入上均产生整体匹配。
test "demo every pattern matches its sample" {
  for case in demo_cases() {
    let (pat, input) = case
    match Pattern::compile(pat) {
      Ok(p) =>
        match p.find(input) {
          Some(_) => ()
          None => fail("demo pattern did not match sample: " + pat)
        }
      Err(_) => fail("demo pattern failed to compile: " + pat)
    }
  }
}

///|
/// email：命名捕获 user / domain（编号 1 / 2），整体匹配与捕获子串（R11.2）。
test "demo email captures user and domain" {
  let input = "user_1@example.com"
  match Pattern::compile(demo_email()) {
    Ok(p) =>
      match p.captures(input) {
        Some(caps) => {
          assert_true(caps.group(0) == Some({ start: 0, end: 18 }))
          // 编号 == 命名。
          assert_true(caps.group(1) == caps.name("user"))
          assert_true(caps.group(2) == caps.name("domain"))
          match caps.name("user") {
            Some(m) => @test.assert_eq(dt_slice(input, m), "user_1")
            None => fail("user unset")
          }
          match caps.name("domain") {
            Some(m) => @test.assert_eq(dt_slice(input, m), "example.com")
            None => fail("domain unset")
          }
        }
        None => fail("email did not match")
      }
    Err(_) => fail("email compile failed")
  }
}

///|
/// email：`replace_all` 以 `$2 at $1` 引用捕获组重写（R11.3）。
test "demo email replace references" {
  match Pattern::compile(demo_email()) {
    Ok(p) =>
      @test.assert_eq(
        p.replace_all("user_1@example.com", "$2 at $1"),
        "example.com at user_1",
      )
    Err(_) => fail("email compile failed")
  }
}

///|
/// IPv4：四个八位组各为编号捕获组 1..4（R11.2）。
test "demo ipv4 four octet captures" {
  let input = "192.168.0.1"
  match Pattern::compile(demo_ipv4()) {
    Ok(p) =>
      match p.captures(input) {
        Some(caps) => {
          assert_true(caps.group(0) == Some({ start: 0, end: 11 }))
          @test.assert_eq(dt_slice_opt(input, caps.group(1)), "192")
          @test.assert_eq(dt_slice_opt(input, caps.group(2)), "168")
          @test.assert_eq(dt_slice_opt(input, caps.group(3)), "0")
          @test.assert_eq(dt_slice_opt(input, caps.group(4)), "1")
        }
        None => fail("ipv4 did not match")
      }
    Err(_) => fail("ipv4 compile failed")
  }
}

///|
/// ISO 日期：命名捕获 year / month / day，`replace_all` 重排为 day/month/year（R11.2/11.3）。
test "demo iso date captures and rearrange" {
  let input = "2026-06-12"
  match Pattern::compile(demo_iso_date()) {
    Ok(p) => {
      match p.captures(input) {
        Some(caps) => {
          assert_true(caps.group(0) == Some({ start: 0, end: 10 }))
          @test.assert_eq(dt_slice_opt(input, caps.name("year")), "2026")
          @test.assert_eq(dt_slice_opt(input, caps.name("month")), "06")
          @test.assert_eq(dt_slice_opt(input, caps.name("day")), "12")
        }
        None => fail("iso date did not match")
      }
      // 命名引用重排。
      @test.assert_eq(
        p.replace_all(input, "${day}/${month}/${year}"),
        "12/06/2026",
      )
    }
    Err(_) => fail("iso date compile failed")
  }
}

///|
/// 数字字面量：整数 / 小数 / 指数整体匹配，可选小数与指数子组（R11.2）。
test "demo number integer decimal exponent" {
  let input = "-12.5e+3"
  match Pattern::compile(demo_number()) {
    Ok(p) =>
      match p.captures(input) {
        Some(caps) => {
          assert_true(caps.group(0) == Some({ start: 0, end: 8 }))
          // 小数部分子组 ".5"、指数部分子组 "e+3"。
          @test.assert_eq(dt_slice_opt(input, caps.group(1)), ".5")
          @test.assert_eq(dt_slice_opt(input, caps.group(2)), "e+3")
        }
        None => fail("number did not match")
      }
    Err(_) => fail("number compile failed")
  }
}

///|
/// 数字字面量：纯整数样例，小数 / 指数子组未设置（R11.2 / R1.5）。
test "demo number plain integer leaves optional groups unset" {
  match Pattern::compile(demo_number()) {
    Ok(p) =>
      match p.captures("42") {
        Some(caps) => {
          assert_true(caps.group(0) == Some({ start: 0, end: 2 }))
          assert_true(caps.group(1) == None)
          assert_true(caps.group(2) == None)
        }
        None => fail("number did not match plain integer")
      }
    Err(_) => fail("number compile failed")
  }
}

///|
/// 小工具：取可选匹配区间的子串切片；未设置返回空串。
fn dt_slice_opt(input : String, m : Match?) -> String {
  match m {
    Some(mm) => dt_slice(input, mm)
    None => ""
  }
}
