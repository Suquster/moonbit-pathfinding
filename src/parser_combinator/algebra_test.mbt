// algebra_test.mbt —— L0 代数核心原语（algebra.mbt）的单元测试。
//
// 对应 tasks.md 任务 1.1 的实现自洽校验：在小型确定性夹具上验证 `pure` /
// `map` / `bind` / `ap` / `pfail` 的成功、失败与「不消费输入」契约
// （R1.1~R1.5）。本文件聚焦**具体示例与边界**；以全称量化形式表述的核心
// 代数定律（functor / monad / applicative / alternative，Property 1~10）由
// 任务 1.2~1.5 的属性测试单独承载。
//
// 约定：对 `Option` / `Array` 等复合类型的等值校验采用 `assert_true(x == y)`
// （走 `Eq`），以避免触发 `Show`-用于-debug 的弃用告警，保持本包零告警。

///|
/// pure 恒成功、产出给定值、且不消费输入（剩余输入位置与进入位置一致）。
test "pure succeeds with value and consumes nothing" {
  let input = Input::from_string("abc")
  match pure(42).parse(input) {
    Ok(v, rest) => {
      @test.assert_eq(v, 42)
      // 零消费：剩余输入仍指向起始位置。
      @test.assert_eq(rest.pos.offset, 0)
      assert_true(rest.peek() == Some('a'))
    }
    Fail(_, ..) => fail("pure should never fail")
  }
}

///|
/// map 成功时施加 f，并保持与底层解析器相同的消费量。
test "map applies function and preserves consumption" {
  // any_char 成功消费一位；map 把字符转为其 Int 码位，消费量应保持不变。
  let p = map(any_char(), fn(c) { c.to_int() })
  match p.parse_string("A") {
    Ok(v, rest) => {
      @test.assert_eq(v, 'A'.to_int())
      @test.assert_eq(rest.pos.offset, 1) // 与 any_char 一致地消费了一位
    }
    Fail(_, ..) => fail("expected success")
  }
}

///|
/// map 失败时原样透传底层失败的位置与期望符号（不调用 f）。
test "map propagates failure verbatim without calling f" {
  // 以可变单元格记录 f 是否被调用；底层 pchar 失败应令 f 永不触发。
  let called = [false]
  let p = map(pchar('x'), fn(_c) {
    called[0] = true
    0
  })
  match p.parse_string("abc") {
    Fail(pos, expected~) => {
      @test.assert_eq(pos.offset, 0)
      assert_true(expected == ["'x'"]) // 与 pchar('x') 的期望逐元素一致
    }
    Ok(_, _) => fail("expected failure")
  }
  assert_false(called[0]) // f 未被调用
}

///|
/// bind 成功时在剩余输入上运行 f(v) 返回的解析器（依赖式串联）。
test "bind sequences dependent parsers" {
  // 先读一个字符，再要求紧随其后出现同一个字符（依赖前驱产出值）。
  let p = bind(any_char(), fn(c) { pchar(c) })
  match p.parse_string("aab") {
    Ok(v, rest) => {
      @test.assert_eq(v, 'a')
      @test.assert_eq(rest.pos.offset, 2) // 消费了两个 'a'
      assert_true(rest.peek() == Some('b'))
    }
    Fail(_, ..) => fail("expected success")
  }
  // 第二个字符不等于第一个 → 整体失败。
  assert_false(p.parse_string("ab").is_ok())
}

///|
/// bind 失败时原样透传底层失败且不调用 f。
test "bind propagates failure verbatim without calling f" {
  let called = [false]
  let p = bind(pchar('x'), fn(_c) {
    called[0] = true
    pure('y')
  })
  match p.parse_string("abc") {
    Fail(pos, expected~) => {
      @test.assert_eq(pos.offset, 0)
      assert_true(expected == ["'x'"])
    }
    Ok(_, _) => fail("expected failure")
  }
  assert_false(called[0]) // f 未被调用
}

///|
/// ap：先解析出函数再解析出实参并应用（applicative apply）。
test "ap applies parsed function to parsed argument" {
  // pf 不消费输入、产出"加一"函数；pa 解析一个数字字符并转为其数值。
  let pf : Parser[(Int) -> Int] = pure(fn(n) { n + 1 })
  let pa = map(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字"), fn(c) {
    c.to_int() - '0'.to_int()
  })
  match ap(pf, pa).parse_string("7") {
    Ok(v, _) => @test.assert_eq(v, 8)
    Fail(_, ..) => fail("expected success")
  }
}

///|
/// pfail 恒失败、不消费输入，并携带给定的期望符号集合。
test "pfail always fails with given expected and consumes nothing" {
  let p : Parser[Int] = pfail(expected=["期望符号"])
  match p.parse_string("abc") {
    Fail(pos, expected~) => {
      @test.assert_eq(pos.offset, 0) // 失败位置即进入位置（不消费）
      assert_true(expected == ["期望符号"])
    }
    Ok(_, _) => fail("pfail should never succeed")
  }
}

///|
/// alt 左单位元的具体见证：alt([pfail, p]) 与 p 产生一致结果（Property 9 的样例）。
test "alt with leading pfail behaves like the surviving branch" {
  let p = pchar('a')
  let lhs = alt([pfail(expected=["zero"]), p])
  match lhs.parse_string("abc") {
    Ok(v, rest) => {
      @test.assert_eq(v, 'a')
      @test.assert_eq(rest.pos.offset, 1)
    }
    Fail(_, ..) => fail("expected success")
  }
}
