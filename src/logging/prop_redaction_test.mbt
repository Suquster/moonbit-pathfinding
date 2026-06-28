// prop_redaction_test.mbt —— 脱敏完整性属性测试（任务 10.2）。
//
//   Feature: logging, Property 12: 脱敏完整性（redaction-completeness）
//   --------------------------------------------------------------------
//   *对任意* （敏感字段集 / 谓词, 事件）对，脱敏后输出满足：每个被判定为敏感的
//   字段取值等于固定掩码（即使原值为嵌套 VMap/VList 也整体替换，内部无原值片段
//   残留），且脱敏后字段键集合与脱敏前逐一致、非敏感字段取值不变。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 本地包含判定（黑盒测试不可见源包私有 array_contains）。
fn rd_contains(arr : Array[String], target : String) -> Bool {
  for x in arr {
    if x == target {
      return true
    }
  }
  false
}

///|
/// 单次场景：随机敏感字段集 + 谓词（命中 "email"），随机（可嵌套）字段事件，
/// 脱敏后断言：键集合不变、敏感字段取值 == 掩码、非敏感字段取值不变。
fn rd_completeness(rng : @infra_pbt.Rng) -> Bool {
  let names = ["password", "token", "ssn", "email", "user", "count"]
  let sensitive : Array[String] = []
  for nm in names {
    if rng.next_bool() {
      sensitive.push(nm)
    }
  }
  let pred = fn(k : String, _v : Value) -> Bool { k == "email" }
  let policy = RedactionPolicy::by_names(sensitive).with_predicate(pred)
  let fields : Map[String, Value] = {}
  for nm in names {
    if rng.next_bool() {
      fields[nm] = sh_value(rng, 2) // 可能为嵌套 VMap/VList
    }
  }
  let e = Event::new(0L, Level::Info, fields)
  let red = redact(policy, e)
  // 键集合不变（同尺寸 + 每键存在）。
  if red.fields.length() != e.fields.length() {
    return false
  }
  let mut ok = true
  e.fields.each(fn(k, v) {
    match red.fields.get(k) {
      None => ok = false
      Some(rv) => {
        let is_sensitive = rd_contains(sensitive, k) || pred(k, v)
        if is_sensitive {
          if !(rv == redaction_mask) {
            ok = false
          }
        } else if !(rv == v) {
          ok = false
        }
      }
    }
  })
  // ts / level 不变。
  if red.ts != e.ts || !(red.level == e.level) {
    ok = false
  }
  ok
}

///|
/// Feature: logging, Property 12: 脱敏完整性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5**
test "Feature: logging, Property 12: redaction-completeness (holds_for_all)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { rd_completeness(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
