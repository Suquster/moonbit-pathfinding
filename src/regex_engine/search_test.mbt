// search_test.mbt —— 高层搜索 API `Pattern` 单元测试（任务 9.4）。
//
// 对应 design.md §4.10（R8）。覆盖 `find_all`/`replace`/`replace_all`/`split`/
// `captures` 的代表样例，以及空匹配前进与命名引用替换等边界。
//
// _Requirements: 8.1, 8.5, 8.6, 8.7_

///|
/// 小工具：取字符数组 `[a,b)` 切片为字符串（与 search.mbt 内部约定一致）。
fn st_slice(input : String, m : Match) -> String {
  let chars = input.iter().to_array()
  let mut s = ""
  for k in m.start..<m.end {
    s = s + chars[k].to_string()
  }
  s
}

///|
/// find_all：在 "banana" 上枚举全部不重叠 'a'（R8.1/8.2）。
test "search find_all enumerates non-overlapping matches" {
  match Pattern::compile("a") {
    Ok(p) => {
      let ms = p.find_all("banana")
      @test.assert_eq(ms.length(), 3)
      assert_true(ms[0] == { start: 1, end: 2 })
      assert_true(ms[1] == { start: 3, end: 4 })
      assert_true(ms[2] == { start: 5, end: 6 })
    }
    Err(_) => fail("compile failed for a")
  }
}

///|
/// find_all：多字符 token `ab` 不重叠枚举（相邻匹配不共享字符，R8.2）。
test "search find_all multi-char token" {
  match Pattern::compile("ab") {
    Ok(p) => {
      let ms = p.find_all("ababxab")
      @test.assert_eq(ms.length(), 3)
      assert_true(ms[0] == { start: 0, end: 2 })
      assert_true(ms[1] == { start: 2, end: 4 })
      assert_true(ms[2] == { start: 5, end: 7 })
    }
    Err(_) => fail("compile failed for ab")
  }
}

///|
/// find_all：空匹配 `a*` 至少前进一字符，枚举有限终止（R8.3）。
test "search find_all empty match advances and terminates" {
  match Pattern::compile("a*") {
    Ok(p) => {
      let input = "bab"
      let ms = p.find_all(input)
      let n = input.iter().to_array().length()
      // 有限终止：匹配数不超过 n+1。
      assert_true(ms.length() <= n + 1)
      // 不重叠：相邻匹配 start 不小于前一匹配 end。
      let mut i = 1
      while i < ms.length() {
        assert_true(ms[i].start >= ms[i - 1].end)
        i = i + 1
      }
    }
    Err(_) => fail("compile failed for a*")
  }
}

///|
/// captures：编号组与命名组检索一致，未设置组返回 None（R8.4）。
test "search captures numbered and named groups" {
  match Pattern::compile("(?<user>[a-z]+)@(?<host>[a-z]+)") {
    Ok(p) =>
      match p.captures("bob@host") {
        Some(caps) => {
          // 第 0 组为整体匹配。
          assert_true(caps.group(0) == Some({ start: 0, end: 8 }))
          // 编号 1/2 == 命名 user/host。
          assert_true(caps.group(1) == caps.name("user"))
          assert_true(caps.group(2) == caps.name("host"))
          // 切片等于实际匹配子串。
          match caps.name("user") {
            Some(m) => @test.assert_eq(st_slice("bob@host", m), "bob")
            None => fail("user group unset")
          }
          match caps.name("host") {
            Some(m) => @test.assert_eq(st_slice("bob@host", m), "host")
            None => fail("host group unset")
          }
          // 未知名称返回 None。
          assert_true(caps.name("missing") == None)
        }
        None => fail("no captures for email")
      }
    Err(_) => fail("compile failed for email pattern")
  }
}

///|
/// captures：未走通的择一分支组返回未设置（None），整体仍匹配（R8.4 / R1.5）。
test "search captures unset group returns None" {
  match Pattern::compile("(a)|(b)") {
    Ok(p) =>
      match p.captures("b") {
        Some(caps) => {
          assert_true(caps.group(0) == Some({ start: 0, end: 1 }))
          // 第 1 组（a 分支）未参与匹配。
          assert_true(caps.group(1) == None)
          // 第 2 组（b 分支）已设置。
          assert_true(caps.group(2) == Some({ start: 0, end: 1 }))
        }
        None => fail("no captures for (a)|(b)")
      }
    Err(_) => fail("compile failed for (a)|(b)")
  }
}

///|
/// replace：仅替换首个匹配（R8.5）。
test "search replace first match only" {
  match Pattern::compile("a") {
    Ok(p) => @test.assert_eq(p.replace("banana", "X"), "bXnana")
    Err(_) => fail("compile failed for a")
  }
}

///|
/// replace_all：替换全部不重叠匹配（R8.5）。
test "search replace_all every match" {
  match Pattern::compile("a") {
    Ok(p) => @test.assert_eq(p.replace_all("banana", "X"), "bXnXnX")
    Err(_) => fail("compile failed for a")
  }
}

///|
/// replace_all：捕获组引用 `$1`/`$2` 与字面 `$$`（R8.6）。
test "search replace_all numbered group references" {
  match Pattern::compile("(a)(b)") {
    Ok(p) => {
      // 交换两组。
      @test.assert_eq(p.replace_all("abab", "$2$1"), "baba")
      // 字面 '$'。
      @test.assert_eq(p.replace_all("ab", "$$"), "$")
    }
    Err(_) => fail("compile failed for (a)(b)")
  }
}

///|
/// replace_all：命名组引用 `${name}`（R8.6）。
test "search replace_all named group references" {
  match Pattern::compile("(?<x>a)(?<y>b)") {
    Ok(p) => @test.assert_eq(p.replace_all("ab", "${y}-${x}"), "b-a")
    Err(_) => fail("compile failed for named groups")
  }
}

///|
/// split：以匹配区间为分隔切分（R8.7）。
test "search split on separator" {
  match Pattern::compile(",") {
    Ok(p) => {
      let parts = p.split("a,b,c")
      @test.assert_eq(parts.length(), 3)
      @test.assert_eq(parts[0], "a")
      @test.assert_eq(parts[1], "b")
      @test.assert_eq(parts[2], "c")
    }
    Err(_) => fail("compile failed for ,")
  }
}

///|
/// split：无分隔符时返回整串单元素；前后空串保留。
test "search split edge cases" {
  match Pattern::compile(",") {
    Ok(p) => {
      // 无匹配：返回整串。
      let whole = p.split("abc")
      @test.assert_eq(whole.length(), 1)
      @test.assert_eq(whole[0], "abc")
      // 前导/尾随分隔符产生空串片段。
      let parts = p.split(",a,")
      @test.assert_eq(parts.length(), 3)
      @test.assert_eq(parts[0], "")
      @test.assert_eq(parts[1], "a")
      @test.assert_eq(parts[2], "")
    }
    Err(_) => fail("compile failed for ,")
  }
}
