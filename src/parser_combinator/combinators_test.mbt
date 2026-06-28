// combinators_test.mbt —— 组合子（seq / alt / many / many1 / optional）的单元测试。
//
// 对应任务 5.2：在小型确定性夹具上校验组合子的成功、失败与回溯（backtracking）
// 契约——成功返回产出值与剩余输入（R4.2）；失败返回含位置与期望符号且不消费
// 输入（R4.3）；择一分支失败时回溯到分支起点（R4.4）。解析器契约不变量与语法
// 往返性质的属性测试由后续任务 5.3 / 5.4 单独承载。
//
// 说明：对 `Option` / `Array` / 元组等复合类型采用 `assert_true(x == y)`（走
// `Eq`），以避免触发 `Show`-用于-debug 的弃用告警，保持本包零告警。

///|
/// seq 成功：依次匹配两个字符，产出二元组并消费两位。
test "seq succeeds and pairs results" {
  let p = seq(pchar('a'), pchar('b'))
  let result = p.parse_string("abc")
  assert_true(result.is_ok())
  assert_true(result.value() == Some(('a', 'b')))
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some('c'))
    None => fail("expected remaining input")
  }
}

///|
/// seq 失败：第二个子解析器失败时，失败位置定位到其消费处（不返回剩余输入）。
test "seq fails at second parser position" {
  let p = seq(pchar('a'), pchar('b'))
  let result = p.parse_string("axc")
  assert_false(result.is_ok())
  match result {
    Fail(pos, expected~) => {
      inspect(pos, content="1:2")
      @test.assert_eq(pos.offset, 1)
      assert_true(expected == ["'b'"])
    }
    Ok(_, _) => fail("expected failure")
  }
}

///|
/// seq 失败：第一个子解析器失败时定位到起点且传播其期望符号。
test "seq fails at first parser position" {
  let p = seq(pchar('a'), pchar('b'))
  let result = p.parse_string("xbc")
  match result {
    Fail(pos, expected~) => {
      inspect(pos, content="1:1")
      assert_true(expected == ["'a'"])
    }
    Ok(_, _) => fail("expected failure")
  }
}

///|
/// alt 成功：返回首个成功分支的结果。
test "alt returns first matching branch" {
  let p = alt([pchar('a'), pchar('b'), pchar('c')])
  assert_true(p.parse_string("bzz").value() == Some('b'))
  assert_true(p.parse_string("azz").value() == Some('a'))
}

///|
/// alt 回溯：靠前分支消费了部分输入后失败，靠后分支仍从分支起点重新匹配成功。
test "alt backtracks to branch start after partial consumption" {
  // 分支一 "abc" 在匹配到 "ab" 后于第三位失败；分支二 "abx" 应从起点重新成功。
  let p = alt([ptoken("abc"), ptoken("abx")])
  let result = p.parse_string("abxyz")
  assert_true(result.is_ok())
  assert_true(result.value() == Some("abx"))
  match result.rest() {
    Some(rest) => {
      // 回溯后从分支起点重新消费 "abx"，剩余应停在 'y'（offset 3）。
      assert_true(rest.peek() == Some('y'))
      @test.assert_eq(rest.pos.offset, 3)
    }
    None => fail("expected remaining input")
  }
}

///|
/// alt 失败：所有分支失败时在分支起点返回失败并汇总各分支期望符号，且不消费输入。
test "alt fails at start and aggregates expected" {
  let p = alt([pchar('a'), pchar('b')])
  let result = p.parse_string("zzz")
  match result {
    Fail(pos, expected~) => {
      inspect(pos, content="1:1")
      @test.assert_eq(pos.offset, 0)
      assert_true(expected == ["'a'", "'b'"])
    }
    Ok(_, _) => fail("expected failure")
  }
}

///|
/// many 成功：重复匹配收集全部产出，停在首个失败处。
test "many collects repeated matches" {
  let p = many(pchar('a'))
  let result = p.parse_string("aaab")
  assert_true(result.value() == Some(['a', 'a', 'a']))
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some('b'))
    None => fail("expected remaining input")
  }
}

///|
/// many 零次：无任何匹配时成功返回空数组且不消费输入。
test "many succeeds with empty result on zero matches" {
  let p = many(pchar('a'))
  let result = p.parse_string("bbb")
  assert_true(result.is_ok())
  let empty : Array[Char] = []
  assert_true(result.value() == Some(empty))
  match result.rest() {
    Some(rest) => @test.assert_eq(rest.pos.offset, 0)
    None => fail("expected remaining input")
  }
}

///|
/// many1 成功：至少一次匹配，收集全部产出。
test "many1 collects one or more matches" {
  let p = many1(pchar('a'))
  let result = p.parse_string("aab")
  assert_true(result.value() == Some(['a', 'a']))
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some('b'))
    None => fail("expected remaining input")
  }
}

///|
/// many1 失败：首次匹配即失败时返回含位置与期望符号的错误，且不消费输入。
test "many1 fails when first match fails" {
  let p = many1(pchar('a'))
  let result = p.parse_string("bbb")
  match result {
    Fail(pos, expected~) => {
      inspect(pos, content="1:1")
      @test.assert_eq(pos.offset, 0)
      assert_true(expected == ["'a'"])
    }
    Ok(_, _) => fail("expected failure")
  }
}

///|
/// optional 成功：子解析器成功时产出 Some 并消费输入。
test "optional yields Some on success" {
  let p = optional(pchar('a'))
  let result = p.parse_string("abc")
  assert_true(result.value() == Some(Some('a')))
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some('b'))
    None => fail("expected remaining input")
  }
}

///|
/// optional 回溯：子解析器失败时产出 None、回溯到起点且不消费输入。
test "optional yields None and backtracks on failure" {
  let p = optional(pchar('a'))
  let result = p.parse_string("xyz")
  assert_true(result.is_ok())
  assert_true(result.value() == Some(None))
  match result.rest() {
    Some(rest) => {
      assert_true(rest.peek() == Some('x'))
      @test.assert_eq(rest.pos.offset, 0)
    }
    None => fail("expected remaining input")
  }
}

///|
/// 组合示例：seq + many + optional 协同——匹配一个字母后跟随若干数字与可选感叹号。
test "combinators compose for a small grammar" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  let p = seq(seq(pchar('x'), many(digit)), optional(pchar('!')))
  let result = p.parse_string("x123!rest")
  assert_true(result.is_ok())
  match result.value() {
    Some(((head, digits), bang)) => {
      @test.assert_eq(head, 'x')
      assert_true(digits == ['1', '2', '3'])
      assert_true(bang == Some('!'))
    }
    None => fail("expected parsed value")
  }
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some('r'))
    None => fail("expected remaining input")
  }
}
