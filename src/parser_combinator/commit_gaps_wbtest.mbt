// 白盒测试：覆盖率审计收口（INFRA 第六十四批）——
// cut 别名、recover 直通成功路与同步点缺失时的 EOF 兜底。

///|
test "cut：与 commit 同义，成功路直通" {
  let g = cut(lift(pchar('a')))
  match g.run_packrat_string("ab") {
    Ok(v, rest) => {
      assert_eq(v, 'a')
      assert_eq(rest.pos.offset, 1)
    }
    Fail(_, ..) => fail("expected success")
  }
}

///|
test "recover：p 成功时直通不进入恢复扫描" {
  let digit_g = lift(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字"))
  let p = lift(pchar('(')).bind(fn(_) { commit(digit_g) })
  let sync = lift(pchar(',')).map(fn(_c) { () })
  let r = recover(p, sync, '?')
  match r.run_packrat_string("(1x") {
    Ok(v, _) => assert_eq(v, '1')
    Fail(_, ..) => fail("expected pass-through success")
  }
}

///|
test "recover：硬失败后同步点缺失扫描至 EOF 以 fallback 收束" {
  let digit_g = lift(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字"))
  let p = lift(pchar('(')).bind(fn(_) { commit(digit_g) })
  let sync = lift(pchar(',')).map(fn(_c) { () })
  let r = recover(p, sync, '?')
  match r.run_packrat_string("(xyz") {
    Ok(v, rest) => {
      assert_eq(v, '?')
      assert_true(rest.is_eof())
    }
    Fail(_, ..) => fail("expected EOF fallback")
  }
}
