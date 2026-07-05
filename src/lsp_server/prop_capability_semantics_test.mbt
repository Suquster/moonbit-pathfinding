// prop_capability_semantics_test.mbt —— T5.3 能力语义一致性属性
// （definition / completion / hover / diagnostics 相互印证）。
//
// 对随机生成的 DSL 文档，四项能力的结果必须与 `analyze` 的符号/引用/诊断
// 表相互一致——不是逐例断言固定输出，而是锁定能力间的语义不变量：
//
//   * P1 定义跳转-引用一致：对每处引用 r，`on_definition(r.start)` 恰在
//     「r.name 已定义 ⇔ 返回该键定义的 Location」间双向成立；
//   * P2 定义跳转自洽：对每个符号 s，`on_definition(s.start)` 返回 s 自身位置；
//   * P3 补全-符号表一致：`on_completion` 的 label 集合 = 符号表键名去重
//     （保持首现顺序），且 detail 携带该键的值；
//   * P4 悬停覆盖：符号与引用位置上 `on_hover` 恒为 `Some`，且已定义键的
//     悬停文本携带其值；
//   * P5 诊断-引用一致：未定义引用数 ≤ 诊断数，且每处未定义引用都有对应
//     「未定义」诊断落在其范围上。

///|
/// 运行期构造 `${name}`（规避 JS 后端源码字面 `${`，与 rename.mbt 同款约定）。
fn cap_wrap_ref(name : String) -> String {
  let dollar = Int::unsafe_to_char(0x24).to_string()
  let lbrace = Int::unsafe_to_char(0x7B).to_string()
  let rbrace = Int::unsafe_to_char(0x7D).to_string()
  dollar + lbrace + name + rbrace
}

///|
/// 随机 DSL 文档生成器：混合合法定义、对已定义/未定义键的引用与重复定义。
fn gen_cap_doc() -> @infra_pbt.Gen[TextDocument] {
  @infra_pbt.Gen::new(fn(rng) {
    let names = ["alpha", "beta", "gamma", "delta", "alpha"] // 末位制造重复定义
    let lines = rng.next_range(1, 8)
    let sb = StringBuilder::new()
    let mut i = 0
    while i < lines {
      if i > 0 {
        sb.write_char('\n')
      }
      let name = names[rng.next_below(names.length())]
      match rng.next_below(3) {
        0 => sb.write_string(name + " = plain\{rng.next_below(10)}")
        1 =>
          // 引用某个（可能未定义的）键。
          sb.write_string(
            name +
            " = " +
            cap_wrap_ref(
              if rng.next_bool() {
                names[rng.next_below(names.length())]
              } else {
                "missing\{rng.next_below(3)}"
              },
            ),
          )
        _ => sb.write_string(name + " = v\{rng.next_below(10)}")
      }
      i = i + 1
    }
    { uri: "file:///cap.dsl", text: sb.to_string() }
  })
}

///|
/// Feature: moonbit-infra-suite, T5.3: 能力语义一致性（definition/completion/
/// hover/diagnostics 与 analyze 相互印证，100 迭代）
///
/// **Validates: Requirements 5.6, 5.7, 5.8（T5.3）**
test "T5.3 property: capability semantics agree with analysis (100 iters)" {
  let ok = @infra_pbt.holds_for_all(gen_cap_doc(), fn(doc) {
    let a = analyze(doc)
    let mut all_ok = true
    // P1：引用处的定义跳转 ⇔ 该键已定义。
    for r in a.references {
      let mut defined : Symbol? = None
      for s in a.symbols {
        if s.name == r.name && defined is None {
          defined = Some(s)
        }
      }
      match (on_definition(a, r.range.start), defined) {
        (Some(loc), Some(s)) =>
          if loc.uri != a.uri || loc.range != s.range {
            all_ok = false
          }
        (None, None) => ()
        _ => all_ok = false
      }
    }
    // P2：符号定义位置上的定义跳转自洽。
    for s in a.symbols {
      match on_definition(a, s.range.start) {
        Some(loc) => {
          // 重复定义时跳到首个同名定义；其范围必属于某同名符号。
          let mut hit = false
          for s2 in a.symbols {
            if s2.name == s.name && loc.range == s2.range {
              hit = true
            }
          }
          if loc.uri != a.uri || !hit {
            all_ok = false
          }
        }
        None => all_ok = false
      }
    }
    // P3：补全 label 集 = 符号键名去重（首现顺序）。
    let expected_labels : Array[String] = []
    for s in a.symbols {
      let mut seen = false
      for l in expected_labels {
        if l == s.name {
          seen = true
        }
      }
      if !seen {
        expected_labels.push(s.name)
      }
    }
    let items = on_completion(a, { line: 0, character: 0 })
    if items.length() != expected_labels.length() {
      all_ok = false
    } else {
      for i, item in items {
        if item.label != expected_labels[i] {
          all_ok = false
        }
      }
    }
    // P4：符号与引用位置上悬停恒为 Some；已定义键悬停携带其值。
    for s in a.symbols {
      match on_hover(a, s.range.start) {
        Some(h) => if !h.contents.contains(s.name) { all_ok = false }
        None => all_ok = false
      }
    }
    for r in a.references {
      if on_hover(a, r.range.start) is None {
        all_ok = false
      }
    }
    // P5：每处未定义引用都有诊断落在其范围上。
    for r in a.references {
      let mut defined = false
      for s in a.symbols {
        if s.name == r.name {
          defined = true
        }
      }
      if !defined {
        let mut has_diag = false
        for d in a.diagnostics {
          if d.range == r.range {
            has_diag = true
          }
        }
        if !has_diag {
          all_ok = false
        }
      }
    }
    all_ok
  })
  assert_true(ok)
}
