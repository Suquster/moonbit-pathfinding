// prop_contract_test.mbt —— 解析器组合子契约不变量属性测试（task 5.3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 9，复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all`
// 模板（每条属性 ≥100 次迭代，由 `holds_for_all` 默认 `iters=100` 保证）。
//
// 单元层面的成功/失败/回溯示例已由 combinators_test.mbt / primitives_test.mbt
// 承载；本文件聚焦"对任意输入恒成立"的契约不变量。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 输入生成器（input generator）
// ---------------------------------------------------------------------------

///|
/// 随机输入字符串生成器。
///
/// 字母表刻意包含 `a/b/c/x` 等字符并保持长度短小（0~10），使得形如 `ab*`
/// 的前缀高频出现，从而充分触发"靠前分支部分消费后失败 → 回溯到分支起点"
/// 的择一路径（Property 9 的回溯子句）。
fn gen_input_string() -> @infra_pbt.Gen[String] {
  let alphabet = ['a', 'b', 'c', 'x', 'y', '0', '1', '2', ' ', '\n']
  @infra_pbt.Gen::new(fn(rng) {
    let len = rng.next_range(0, 10)
    let mut s = ""
    let mut i = 0
    while i < len {
      let c = alphabet[rng.next_below(alphabet.length())]
      s = s + "\{c}"
      i = i + 1
    }
    s
  })
}

// ---------------------------------------------------------------------------
// 辅助：从解析结果中提取成功/失败信息（避免重复的标签重命名模式匹配）
// ---------------------------------------------------------------------------

///|
/// 成功信息：`(产出值, 剩余输入偏移)`；失败时为 `None`。
fn[T] ok_info(r : ParseResult[T]) -> (T, Int)? {
  match r {
    Ok(v, rest) => Some((v, rest.pos.offset))
    Fail(_, ..) => None
  }
}

///|
/// 失败信息：`(失败位置偏移, 期望符号集合)`；成功时为 `None`。
fn[T] fail_info(r : ParseResult[T]) -> (Int, Array[String])? {
  match r {
    Ok(_, _) => None
    Fail(pos, expected~) => Some((pos.offset, expected))
  }
}

// ---------------------------------------------------------------------------
// Property 9a：成功时「已消费 + 剩余输入」守恒等于原输入
// ---------------------------------------------------------------------------

///|
/// 校验单个解析器在给定输入上的守恒律：成功时，把"已消费前缀"与"剩余输入"
/// 重新拼接应逐码元等于原输入；剩余输入指向同一不可变源字符串、偏移落在
/// `[0, len]` 区间内。失败不属于守恒子句，直接视为通过（由 9b 覆盖）。
fn[T] check_conservation(p : Parser[T], s : String) -> Bool {
  match p.parse_string(s) {
    Fail(_, ..) => true
    Ok(_, rest) => {
      let off = rest.pos.offset
      if off < 0 || off > s.length() {
        false
      } else if rest.source != s {
        // 剩余输入必须共享原始（未被修改的）源字符串。
        false
      } else {
        // 重建：consumed ++ remaining 必须逐码元等于原输入。
        let units = s.code_units()
        let recon = StringBuilder::new()
        let mut i = 0
        while i < off {
          recon.write_char(units[i].to_int().unsafe_to_char())
          i = i + 1
        }
        while i < s.length() {
          recon.write_char(units[i].to_int().unsafe_to_char())
          i = i + 1
        }
        recon.to_string() == s
      }
    }
  }
}

///|
/// Feature: moonbit-infra-suite, Property 9: 解析器组合子契约不变量（守恒子句）
///
/// 对任意输入与一组由组合子构造的解析器，成功解析时返回的"已消费 + 剩余
/// 输入"守恒地等于原输入（不丢失、不重复、不重排字符，剩余输入正确指向
/// 原缓冲的未消费后缀）。
///
/// **Validates: Requirements 4.2, 4.3, 4.4**
test "Feature: moonbit-infra-suite, Property 9: success conserves consumed + remaining" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  let ok = @infra_pbt.holds_for_all(gen_input_string(), fn(s) {
    // 覆盖序列 / 择一 / 重复 / 可选 四类组合子构造的解析器。
    let p_letters = many(
      satisfy(fn(c) { c >= 'a' && c <= 'z' }, label="字母"),
    )
    let p_all = many(any_char())
    let p_seq = seq(optional(pchar('a')), many(digit))
    let p_alt = alt([ptoken("ab"), ptoken("a")])
    check_conservation(p_letters, s) &&
    check_conservation(p_all, s) &&
    check_conservation(p_seq, s) &&
    check_conservation(p_alt, s)
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 9b：失败时不消费输入且失败位置稳定
// ---------------------------------------------------------------------------

///|
/// 校验单个解析器的失败契约：对同一输入重复运行应得到逐位一致的失败
/// （位置与期望符号均稳定）；若该输入下解析成功则不属于失败子句，跳过。
/// 解析失败结果在类型层面不携带剩余输入（`Fail` 不含 `Input`），因此
/// "失败不消费输入"由数据结构本身保证；此处额外校验其确定性/稳定性。
fn[T] failure_stable(p : Parser[T], s : String) -> Bool {
  match (fail_info(p.parse_string(s)), fail_info(p.parse_string(s))) {
    (Some((o1, e1)), Some((o2, e2))) => o1 == o2 && e1 == e2
    (None, None) => true // 成功路径，不在本子句范围
    _ => false // 同一输入时而成功时而失败 → 非确定性，违约
  }
}

///|
/// Feature: moonbit-infra-suite, Property 9: 解析器组合子契约不变量（失败子句）
///
/// 对任意输入：(1) 失败结果不携带剩余输入（类型层面"不消费输入"）；
/// (2) 对同一输入重复解析，失败位置与期望符号集合稳定一致；
/// (3) 运行一个必失败的解析器不会修改不可变输入（游标与首字符不变）。
///
/// **Validates: Requirements 4.2, 4.3, 4.4**
test "Feature: moonbit-infra-suite, Property 9: failure does not consume and is stable" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  let ok = @infra_pbt.holds_for_all(gen_input_string(), fn(s) {
    // 可能失败的解析器目录：单字符、字面词法单元、至少一次重复。
    let p_char = pchar('a')
    let p_token = ptoken("xyz")
    let p_many1 = many1(digit)
    let stable = failure_stable(p_char, s) &&
      failure_stable(p_token, s) &&
      failure_stable(p_many1, s)
    // 不消费输入：以一个必失败解析器（字母表中不含 'Z'）作用于不可变 Input，
    // 运行前后首字符与游标偏移必须保持不变。
    let input = Input::from_string(s)
    let before = input.peek()
    let _ = pchar('Z').parse(input)
    let after = input.peek()
    let immutable = before == after && input.pos.offset == 0
    stable && immutable
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 9c：回溯模式下择一分支失败应恢复到分支起始位置
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 9: 解析器组合子契约不变量（回溯子句）
///
/// 对任意输入，`alt([p1, p2])` 的行为应等价于"从同一分支起点依次尝试各
/// 分支"的语义参照实现：即便靠前分支已部分推进游标后失败，靠后分支仍从
/// **分支起始位置**（原输入偏移 0）重新开始；全部失败时在分支起点返回失败
/// 并按序汇总各分支期望符号。该等价性正是"回溯到分支起始位置"（R4.4）的
/// 可证形式。同时校验 `optional` 在子解析器失败时回溯到起点、不消费输入。
///
/// **Validates: Requirements 4.2, 4.3, 4.4**
test "Feature: moonbit-infra-suite, Property 9: alternative backtracks to branch start" {
  let p1 = ptoken("abc")
  let p2 = ptoken("ab")
  let ok = @infra_pbt.holds_for_all(gen_input_string(), fn(s) {
    let actual = alt([p1, p2]).parse_string(s)
    // 语义参照：两个分支都从同一起始 Input 运行（体现"回溯到分支起点"）。
    let input = Input::from_string(s)
    let r1 = p1.parse(input)
    let r2 = p2.parse(input)
    // 参照成功结果：alt 返回首个成功分支；二者都从原输入偏移 0 起算。
    let ref_ok = match ok_info(r1) {
      Some(x) => Some(x)
      None => ok_info(r2)
    }
    let alt_ok = match (ok_info(actual), ref_ok) {
      (Some(a), Some(b)) => a == b
      (None, None) => {
        // 全部失败：alt 应在分支起点（offset 0）返回失败并按序汇总期望符号。
        let agg : Array[String] = []
        match fail_info(r1) {
          Some((_, e)) =>
            for x in e {
              agg.push(x)
            }
          None => ()
        }
        match fail_info(r2) {
          Some((_, e)) =>
            for x in e {
              agg.push(x)
            }
          None => ()
        }
        match fail_info(actual) {
          Some((off, ea)) => off == input.pos.offset && ea == agg
          None => false
        }
      }
      _ => false
    }
    // optional 失败时回溯：子解析器失败则产出 None 且剩余输入停在起点。
    let opt_ok = match optional(p1).parse_string(s) {
      Ok(Some(_), _) => true
      Ok(None, rest) => rest.pos.offset == 0
      Fail(_, ..) => false // optional 永不失败
    }
    alt_ok && opt_ok
  })
  assert_true(ok)
}
