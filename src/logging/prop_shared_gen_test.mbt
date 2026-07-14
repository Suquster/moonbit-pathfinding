// prop_shared_gen_test.mbt —— 旗舰深化属性测试的共享生成器（generators）。
//
// 本文件不含 `test` 块，仅提供被多个 `prop_*_test.mbt` 复用的确定性生成器，
// 复用 `@infra_pbt.Rng` 种子驱动随机源（三后端逐位一致、可重放）。所有生成器
// 以 `sh_` 前缀命名，与既有 `prop_roundtrip_test.mbt`（`rt_`）/
// `prop_level_span_test.mbt`（`ls_`）的前缀互不冲突。
//
// 生成空间的可往返约束（与既有 prop_roundtrip_test.mbt 同源）：
//   * 字符串取自含转义/控制字符的 ASCII 字母表（覆盖 json_escape 全分支，且
//     纯 ASCII 保证 Bytes 桥接无损）；
//   * 浮点限定为「奇数 / 8」形态 `(2k+1)/8`：分母为 2 的幂 ⇒ Double 可精确表示
//     并逐位还原，分子为奇数 ⇒ 恒含小数部分 ⇒ 解析判为浮点（不退化为整数）。

///|
/// 随机日志级别：等概率 Trace / Debug / Info / Warn / Error。
fn sh_level(rng : @infra_pbt.Rng) -> Level {
  match rng.next_below(5) {
    0 => Trace
    1 => Debug
    2 => Info
    3 => Warn
    _ => Error
  }
}

///|
/// 随机字符串（长度 0~6）：取自含命名转义、`\u00XX` 控制字符的 ASCII 字母表。
fn sh_string(rng : @infra_pbt.Rng) -> String {
  let alphabet : Array[Char] = [
    'a',
    'b',
    'z',
    'A',
    'M',
    'Z',
    '0',
    '9',
    ' ',
    '/',
    ':',
    '{',
    '}',
    '[',
    ']',
    '"',
    '\\',
    '\n',
    '\r',
    '\t',
    (0x08).unsafe_to_char(),
    (0x0C).unsafe_to_char(),
    (0x01).unsafe_to_char(),
    (0x1F).unsafe_to_char(),
  ]
  let n = rng.next_range(0, 6)
  let mut s = ""
  for _i in 0..<n {
    s = s + alphabet[rng.next_below(alphabet.length())].to_string()
  }
  s
}

///|
/// 可精确往返的浮点：`(2k+1) / 8`，k ∈ [-1000, 1000]（恒非整数、可逐位还原）。
fn sh_float(rng : @infra_pbt.Rng) -> Double {
  let k = rng.next_range(-1000, 1000)
  (2 * k + 1).to_double() / 8.0
}

///|
/// 随机标量取值：等概率 VStr / VInt / VBool / VFloat（均可无损往返）。
fn sh_scalar_value(rng : @infra_pbt.Rng) -> Value {
  match rng.next_below(4) {
    0 => VStr(sh_string(rng))
    1 => VInt(rng.next_range(-1_000_000, 1_000_000).to_int64())
    2 => VBool(rng.next_bool())
    _ => VFloat(sh_float(rng))
  }
}

///|
/// 带深度上界 `budget` 的（可嵌套）取值：budget 用尽则产标量，否则有偏向地
/// 产 VMap / VList（递归 budget-1）或标量。VMap 键取互异形态 `m{i}`。
fn sh_value(rng : @infra_pbt.Rng, budget : Int) -> Value {
  if budget <= 0 {
    return sh_scalar_value(rng)
  }
  match rng.next_below(6) {
    0 => {
      let cnt = rng.next_range(0, 3)
      let m : Map[String, Value] = Map([])
      for i in 0..<cnt {
        m["m\{i}"] = sh_value(rng, budget - 1)
      }
      VMap(m)
    }
    1 => {
      let cnt = rng.next_range(0, 3)
      let xs : Array[Value] = []
      for _i in 0..<cnt {
        xs.push(sh_value(rng, budget - 1))
      }
      VList(xs)
    }
    _ => sh_scalar_value(rng) // 4/6 偏向标量，约束规模
  }
}

///|
/// 仅含标量字段的事件生成器：随机时间戳 / 级别 / 0~4 条唯一键（`k{i}`）标量字段。
fn sh_scalar_event() -> @infra_pbt.Gen[Event] {
  @infra_pbt.Gen::new(fn(rng) {
    let ts = rng.next_range(-1_000_000_000, 1_000_000_000).to_int64()
    let level = sh_level(rng)
    let nf = rng.next_range(0, 4)
    let fields : Map[String, Value] = Map([])
    for i in 0..<nf {
      fields["k\{i}"] = sh_scalar_value(rng)
    }
    Event::new(ts, level, fields)
  })
}

///|
/// 可含任意嵌套深度（上界 3）取值的事件生成器：随机时间戳 / 级别 / 0~4 条字段。
fn sh_nested_event() -> @infra_pbt.Gen[Event] {
  @infra_pbt.Gen::new(fn(rng) {
    let ts = rng.next_range(-1_000_000_000, 1_000_000_000).to_int64()
    let level = sh_level(rng)
    let nf = rng.next_range(0, 4)
    let fields : Map[String, Value] = Map([])
    for i in 0..<nf {
      fields["k\{i}"] = sh_value(rng, 3)
    }
    Event::new(ts, level, fields)
  })
}
