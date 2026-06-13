// redaction.mbt —— 脱敏 / PII 过滤（任务 10.1）。
//
// 设计依据：design.md §4.8「脱敏 / PII 过滤」（Requirement 7.*）。按字段名集合
// 或字段谓词将敏感字段取值**整体**替换为固定掩码，保持字段键集合不变：
//
//   * `redaction_mask` —— 固定掩码标记 `VStr("[REDACTED]")`，不泄露原值任何片段；
//   * `RedactionPolicy::by_names` / `with_predicate` —— 构造脱敏策略；
//   * `redact(policy, e)` —— 对事件施加脱敏：敏感字段（名命中或谓词为真）取值
//     整体替换为掩码（嵌套 `VMap` / `VList` 也整体替换，杜绝深层泄露，
//     Requirement 7.4），其余字段原样保留，字段键集合不变（Requirement 7.3）。

///|
/// 固定掩码标记（Requirement 7 掩码标记）：脱敏后替换原值的常量占位取值。
///
/// 整体常量替换保证脱敏后输出不含任何敏感字段的原始取值片段（Property 12）。
pub let redaction_mask : Value = VStr("[REDACTED]")

///|
/// 脱敏策略：敏感字段名集合 + 可选字段谓词（按名或按谓词判定敏感）。
pub(all) struct RedactionPolicy {
  sensitive : Array[String]
  predicate : (String, Value) -> Bool
}

///|
/// 由敏感字段名集合构造脱敏策略（谓词默认恒假）。
pub fn RedactionPolicy::by_names(names : Array[String]) -> RedactionPolicy {
  { sensitive: names, predicate: fn(_k, _v) { false } }
}

///|
/// 为脱敏策略追加字段谓词：键名命中集合 **或** 谓词为真即判定为敏感。
pub fn RedactionPolicy::with_predicate(
  self : RedactionPolicy,
  pred : (String, Value) -> Bool,
) -> RedactionPolicy {
  { sensitive: self.sensitive, predicate: pred }
}

///|
/// 对事件施加脱敏（Requirement 7.1 / 7.2 / 7.3 / 7.4）。
///
/// 逐字段判定「键名命中 `sensitive` 集合 或 `predicate(key, value)` 为真」：
/// 命中者其取值整体替换为 `redaction_mask`（即使原值为嵌套 `VMap` / `VList`
/// 也整体替换），未命中者原样保留。字段键集合保持不变；时间戳与级别不变。
pub fn redact(policy : RedactionPolicy, e : Event) -> Event {
  let out : Map[String, Value] = Map::new()
  e.fields.each(fn(k, v) {
    let sensitive = array_contains(policy.sensitive, k) ||
      (policy.predicate)(k, v)
    if sensitive {
      out[k] = redaction_mask
    } else {
      out[k] = v
    }
  })
  Event::new(e.ts, e.level, out)
}

///|
/// 数组是否包含某字符串。
fn array_contains(arr : Array[String], target : String) -> Bool {
  for x in arr {
    if x == target {
      return true
    }
  }
  false
}
