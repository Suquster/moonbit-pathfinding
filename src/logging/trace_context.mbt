// trace_context.mbt —— W3C Trace Context 注入 / 提取（任务 9.1）。
//
// 设计依据：design.md §4.7「W3C Trace Context 注入 / 提取」（Requirement 6.*）。
// 桥接既有 `TraceContext` 与 W3C `traceparent` 文本，实现跨进程上下文传播。
// 格式与字段语义追溯 W3C Trace Context 规范（见 README，Requirement 10.3）：
//
//   traceparent = version "-" trace-id "-" parent-id "-" trace-flags
//               = 2hex   "-" 32hex    "-" 16hex     "-" 2hex
//
//   * `inject_traceparent(ctx)` —— 注入为 `00-<32hex>-<16hex>-<01>`（Requirement 6.1）；
//   * `extract_traceparent(s)`  —— 严格校验后提取三分量，非法返回 `None`
//     （Requirement 6.2 / 6.4）；
//   * `W3CContext::is_sampled`   —— trace-flags 最低位为 1 ⟹ 已采样（Requirement 6.3）；
//   * `W3CContext::to_trace_context` —— 桥接回既有 `TraceContext`（Requirement 6.5）。
//
// 实现边界（Requirement 10.6）：内部 `TraceId` / `SpanId` 为 64 位 `Int64`，而
// traceparent trace-id 为 128 位——本库将 64 位标识编码进 trace-id 低 64 位、
// 高 64 位补 0，故 inject 再 extract 对内部标识无损往返（Requirement 6.6 /
// Property 11），此 128↔64 映射在 README 显式声明。

///|
/// W3C traceparent 提取结果：十六进制分量 + flags 整数。
///   * `trace_id` —— 32 位小写 hex；`span_id` —— 16 位小写 hex；
///   * `flags`    —— trace-flags 字节（0..=255），最低位为 sampled 标志。
pub(all) struct W3CContext {
  trace_id : String
  span_id : String
  flags : Int
} derive(Eq, Show)

///|
/// 将既有 `TraceContext` 注入为 traceparent 文本（Requirement 6.1）。
///
/// 内部 64 位 trace 标识编码进 trace-id 低 64 位（高 64 位补 0）得 32 hex；
/// span 标识（缺失时取 0）得 16 hex；flags 默认 `01`（sampled）。
pub fn inject_traceparent(ctx : TraceContext) -> String {
  let trace_low = hex16(ctx.trace.value)
  let trace_id = "0000000000000000" + trace_low
  let span_id = match ctx.span {
    Some(s) => hex16(s.value)
    None => hex16(0L)
  }
  "00-" + trace_id + "-" + span_id + "-01"
}

///|
/// 提取语法合法的 traceparent，还原 trace-id / span-id / flags（Requirement 6.2）。
///
/// 严格校验：恰 4 个 `-` 分隔字段、version 2 hex、trace-id 32 hex、span-id
/// 16 hex、trace-flags 2 hex、各字符为合法 hex。任一不符返回 `None`，不产生
/// 部分构造的上下文（Requirement 6.4 / 13.3）。
pub fn extract_traceparent(s : String) -> W3CContext? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  // 按 '-' 切分为分量。
  let parts : Array[String] = []
  let cur = @infra_text.TextBuilder::new()
  for c in chars {
    if c == '-' {
      parts.push(cur.build())
      cur.reset()
    } else {
      cur.push_char(c)
    }
  }
  parts.push(cur.build())
  // 恰 4 个分量（3 个 '-'）。
  if parts.length() != 4 {
    return None
  }
  let version = parts[0]
  let trace_id = parts[1]
  let span_id = parts[2]
  let flags_str = parts[3]
  if version.length() != 2 ||
    trace_id.length() != 32 ||
    span_id.length() != 16 ||
    flags_str.length() != 2 {
    return None
  }
  if not(is_hex(version)) ||
    not(is_hex(trace_id)) ||
    not(is_hex(span_id)) ||
    not(is_hex(flags_str)) {
    return None
  }
  let flags = match hex_to_int(flags_str) {
    Some(n) => n
    None => return None
  }
  Some({ trace_id, span_id, flags })
}

///|
/// trace-flags 最低位为 1 ⟹ 已采样（sampled，Requirement 6.3）。
pub fn W3CContext::is_sampled(self : W3CContext) -> Bool {
  (self.flags & 1) == 1
}

///|
/// 桥接回既有 `TraceContext`（Requirement 6.5），使可经 `with_context` 续记。
///
/// trace-id 低 64 位 hex → `TraceId.value`；span-id hex → `SpanId.value`
/// （为 0 时视为无激活 span，映射为 `None`）。
pub fn W3CContext::to_trace_context(self : W3CContext) -> TraceContext {
  let trace_low = low16_chars(self.trace_id)
  let trace_value = hex16_to_int64(trace_low)
  let span_value = hex16_to_int64(self.span_id)
  let span : SpanId? = if span_value == 0L {
    None
  } else {
    Some({ value: span_value })
  }
  { trace: ({ value: trace_value } : TraceId), span }
}

// ───────────────────────────── hex 编解码原语 ─────────────────────────────

///|
/// 将 `Int64` 渲染为 16 位小写十六进制（低位在右）。
fn hex16(n : Int64) -> String {
  let out = @infra_text.TextBuilder::new()
  for i = 15; i >= 0; i = i - 1 {
    let nibble = ((n >> (i * 4)) & 0xFL).to_int()
    out.push_str(hex_digit(nibble))
  }
  out.build()
}

///|
/// 判断字符串非空且全部为合法十六进制字符。
fn is_hex(s : String) -> Bool {
  let mut any = false
  for c in s {
    any = true
    let ok = (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')
    if not(ok) {
      return false
    }
  }
  any
}

///|
/// 单个十六进制字符的整数值（非法返回 -1）。
fn hex_char_val(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// 将十六进制字符串解析为非负整数（用于 2 位 flags → 0..255）；非法返回 `None`。
fn hex_to_int(s : String) -> Int? {
  let mut v = 0
  for c in s {
    let d = hex_char_val(c)
    if d < 0 {
      return None
    }
    v = v * 16 + d
  }
  Some(v)
}

///|
/// 将（最多 16 位）十六进制字符串按位拼装为 `Int64`（满 16 位时填满全部 64 位，
/// 最高位进入符号位即视为该位模式的无损还原）。
fn hex16_to_int64(s : String) -> Int64 {
  let mut v : Int64 = 0L
  for c in s {
    let d = hex_char_val(c)
    v = (v << 4) | d.to_int64()
  }
  v
}

///|
/// 取字符串的低 16 个字符（用于从 32 hex 的 trace-id 取低 64 位）。
fn low16_chars(s : String) -> String {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  let n = chars.length()
  let start = if n >= 16 { n - 16 } else { 0 }
  let out = @infra_text.TextBuilder::new()
  for i = start; i < n; i = i + 1 {
    out.push_char(chars[i])
  }
  out.build()
}
