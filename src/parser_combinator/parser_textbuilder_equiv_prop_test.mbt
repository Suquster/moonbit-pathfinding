// parser_textbuilder_equiv_prop_test.mbt —— 任务 12.6 等价性属性测试。
//
// 背景：任务 12.4 已把 parser_combinator 生产源文件中循环内字符串拼接
// （`out = out + ...`）替换为 `@infra_text.TextBuilder`，并以确定性黄金值
// 与 print_json↔parse_json 往返做了固化（见 parser_textbuilder_equiv_test.mbt）。
// 而 JSON 往返属性（parse(print(x))==x）已由 json_prop_test.mbt 的
// `Property 28` 覆盖，故本任务**不重复**往返属性，转而新增一个针对
// 「TextBuilder 改造函数」的**等价性属性测试**：对随机构造的 `Json`，断言
// 生产实现 `print_json`（内部用 `TextBuilder` 顺序物化）与一个**独立参考实现**
// （`Array[String]` + `join`，不依赖 `TextBuilder`）**逐字符相等**。
//
// 这正面验证 Requirement 1.5「替换后每个被改造函数的输出与改造前逐字符相等」：
// 参考实现 `ref_print_json` 等价于改造前的顺序拼接语义，二者对任意输入的逐字符
// 一致即说明 `TextBuilder` 改造未改变可观测输出。
//
// 复用 json_prop_test.mbt 的 `gen_json()`（深度 3 的合法 Json 生成器，含需转义
// 字符），由 @infra_pbt.holds_for_all 以固定种子驱动，≥100 迭代，三后端
// （wasm-gc / js / native）逐位一致、可复现。
//
// 仅新增测试，不改既有签名与既有测试（freeze + bypass）；参考实现内部全部以
// `Array[String]` 收集片段后 `join`，无循环内字符串 `+`。

///|
/// 独立参考实现：打印 JSON 数值（与生产 `print_json_number` 同语义）。
///
/// 整数值打印为整数形式，否则用 `Double` 默认表示。该函数不依赖 `TextBuilder`，
/// 作为「改造前顺序拼接语义」的独立对照基线。
fn ref_print_json_number(d : Double) -> String {
  let i = d.to_int()
  if i.to_double() == d {
    "\{i}"
  } else {
    "\{d}"
  }
}

///|
/// 独立参考实现：打印 JSON 字符串字面量（转义特殊字符）。
///
/// 以 `Array[String]` 收集每个字符 / 转义片段后 `join("")` 物化，等价于改造前
/// 的顺序 `+` 拼接；转义分支与生产 `print_json_string` 完全一致。
fn ref_print_json_string(s : String) -> String {
  let parts : Array[String] = ["\""]
  for c in s {
    if c == '"' {
      parts.push("\\\"")
    } else if c == '\\' {
      parts.push("\\\\")
    } else if c == '\n' {
      parts.push("\\n")
    } else if c == '\r' {
      parts.push("\\r")
    } else if c == '\t' {
      parts.push("\\t")
    } else if c == '\u{0008}' {
      parts.push("\\b")
    } else if c == '\u{000C}' {
      parts.push("\\f")
    } else {
      parts.push(c.to_string())
    }
  }
  parts.push("\"")
  parts.join("")
}

///|
/// 独立参考实现：规范化 JSON 打印器（与生产 `print_json` 同语义）。
///
/// 数组 / 对象元素先收集到 `Array[String]`，再以 `","` 连接并加首尾括号（单次
/// 非循环 `+`，符合 Requirement 1.6 对非循环拼接的放行）。该实现刻意不使用
/// `TextBuilder`，作为生产实现的独立对照。
fn ref_print_json(j : Json) -> String {
  match j {
    JNull => "null"
    JBool(b) => if b { "true" } else { "false" }
    JNumber(d) => ref_print_json_number(d)
    JString(s) => ref_print_json_string(s)
    JArray(items) => {
      let parts : Array[String] = []
      for it in items {
        parts.push(ref_print_json(it))
      }
      "[" + parts.join(",") + "]"
    }
    JObject(pairs) => {
      let parts : Array[String] = []
      for kv in pairs {
        parts.push(ref_print_json_string(kv.0) + ":" + ref_print_json(kv.1))
      }
      "{" + parts.join(",") + "}"
    }
  }
}

///|
/// Feature: production-hardening, Property 1: TextBuilder 改造后 print_json 与独立 join 参考实现逐字符相等
///
/// 对任意由 `gen_json()` 生成的合法 `Json` 值 `x`，生产实现 `print_json(x)`
/// （内部以 `@infra_text.TextBuilder` 物化数组 / 对象 / 字符串转义）与独立的
/// `Array[String] + join` 参考实现 `ref_print_json(x)` 逐字符相等。这见证了
/// 「将循环内 `out = out + ...` 替换为 `TextBuilder` 后输出不变」的等价性契约。
/// 迭代 200 次（≥100 基线），固定种子驱动，三后端结果一致。
///
/// **Validates: Requirements 1.5**
test "Feature: production-hardening, Property 1: print_json TextBuilder 改造与独立 join 参考实现逐字符等价" {
  let ok = @infra_pbt.holds_for_all(
    gen_json(),
    fn(x) { print_json(x) == ref_print_json(x) },
    iters=200,
  )
  assert_true(ok)
}
