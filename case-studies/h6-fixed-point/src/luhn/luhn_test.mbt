// luhn_test.mbt —— Luhn 黑盒测试：黄金向量对拍 + 边界 + 属性遍历。
//
// 黄金向量与 vectors/luhn.psv（gen_vectors.py 再生）逐条一致。

///|
test "luhn_valid：黄金向量对拍（vectors/luhn.psv）" {
  assert_true(@luhn.luhn_valid("79927398713") == Some(true))
  assert_true(@luhn.luhn_valid("49927398716") == Some(true))
  assert_true(@luhn.luhn_valid("49927398717") == Some(false))
  assert_true(@luhn.luhn_valid("1234567812345670") == Some(true))
  assert_true(@luhn.luhn_valid("4111111111111111") == Some(true))
  assert_true(@luhn.luhn_valid("378282246310005") == Some(true))
}

///|
test "luhn_check_digit：黄金向量对拍与诚实边界" {
  assert_true(@luhn.luhn_check_digit("7992739871") == Some(3))
  assert_true(@luhn.luhn_check_digit("411111111111111") == Some(1))
  assert_true(@luhn.luhn_check_digit("123456781234567") == Some(0))
  // 诚实边界：非数字 / 空串显式 None。
  assert_true(@luhn.luhn_valid("4111-1111") is None)
  assert_true(@luhn.luhn_valid("") is None)
  assert_true(@luhn.luhn_check_digit("") is None)
}

///|
test "属性：主体+校验位必然通过校验（0..999 全量遍历）" {
  for n in 0..<1000 {
    let payload = n.to_string()
    match @luhn.luhn_check_digit(payload) {
      Some(d) => {
        assert_true(@luhn.luhn_valid(payload + d.to_string()) == Some(true))
        // 唯一性：其余 9 个校验位必然失败。
        for wrong in 0..<10 {
          if wrong != d {
            assert_true(
              @luhn.luhn_valid(payload + wrong.to_string()) == Some(false),
            )
          }
        }
      }
      None => assert_true(false)
    }
  }
}
