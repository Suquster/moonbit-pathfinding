// luhn.mbt —— Luhn 校验和（ISO/IEC 7812-1 附录 B）。
//
// 应用：银行卡号 / IMEI / 加拿大 SIN 等标识号的防误录校验。
// 诚实边界：含非数字字符或空串显式返回 None，不静默按 0 处理。

///|
/// Luhn 校验：`digits` 为完整号码（含末位校验位）。
/// 从右往左偶数位（0 起）原值、奇数位翻倍后按位相加（>9 减 9），
/// 总和模 10 为 0 即有效。非数字字符或空串返回 None。
pub fn luhn_valid(digits : String) -> Bool? {
  match luhn_sum(digits) {
    Some(sum) => Some(sum % 10 == 0)
    None => None
  }
}

///|
/// 为号码主体（不含校验位）计算 Luhn 校验位（0..9）；
/// 非数字字符或空串返回 None。
pub fn luhn_check_digit(payload : String) -> Int? {
  if payload == "" {
    return None
  }
  // 主体追加占位 0 后求和：校验位 = (10 - sum) % 10。
  match luhn_sum(payload + "0") {
    Some(sum) => Some((10 - sum % 10) % 10)
    None => None
  }
}

///|
/// Luhn 加权数字和；输入非法返回 None。
fn luhn_sum(digits : String) -> Int? {
  let ds : Array[Int] = []
  for c in digits {
    let code = c.to_int()
    if code < '0'.to_int() || code > '9'.to_int() {
      return None
    }
    ds.push(code - '0'.to_int())
  }
  if ds.length() == 0 {
    return None
  }
  let mut sum = 0
  let n = ds.length()
  for i in 0..<n {
    // 从右往左的下标（0 起）：右起偶数位原值，奇数位翻倍。
    let pos = n - 1 - i
    let d = ds[pos]
    if i % 2 == 1 {
      let doubled = d * 2
      sum = sum + (if doubled > 9 { doubled - 9 } else { doubled })
    } else {
      sum = sum + d
    }
  }
  Some(sum)
}
