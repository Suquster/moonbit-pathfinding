// prop_error_conditions_test.mbt —— 非法输入错误条件属性测试（任务 15.2，Property 16）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 16「非法输入错误条件」：
//
//   *对任意* 由生成器产出的非法输入，相应的解码 / 应用函数都以
//   `Result::Err(RpcError)` 失败、且承载**恰当的标准错误码**，绝不 panic/abort，
//   也不产出半成品消息或部分应用文本。三类非法输入分别为：
//     1. 畸形 `Content-Length` 头部帧（缺头部 / 值非非负整数 / 正文长度不足）
//        → `@lsp_binding.decode_framed` 返回 `Err`，错误码为
//        `@lsp_binding.parse_error_code`（-32700）；
//     2. 非法 JSON 正文（无法解析为合法 JSON）→ `@lsp_binding.decode_message`
//        返回 `Err`，错误码为 `@lsp_binding.parse_error_code`；同一非法正文以
//        合法 `Content-Length` 帧包裹后，`@lsp_binding.decode_framed` 亦以
//        `parse_error_code` 失败（帧切分成功、正文解码失败）；
//     3. 越界增量变更（`range` 行号 / 列号越界）→ `apply_changes`（sync.mbt）
//        返回 `Err`，错误码为 `@lsp_binding.invalid_params_code`（-32602），
//        且**不返回部分应用结果**（返回 `Err` 而非携带半成品文本的 `Ok`；纵使
//        其前置有一条合法的全量替换变更，整体仍以 `Err` 失败，前置变更效果不
//        外泄）。
//
// **Validates: Requirements 2.3, 3.5, 11.3**
//
// ── 生成策略（保证「非法」性质确定成立，使属性非平凡且可靠）──────────────────
// 本文件为黑盒测试，仅依赖 @lsp_binding 的公开 API（`decode_framed` /
// `decode_message` / `RpcError` / `parse_error_code` / `invalid_params_code`）
// 与 sync.mbt / position_encoding.mbt 的公开 API（`apply_changes` /
// `ContentChange` / `PositionEncoding`），不触碰任何私有内部工具。文本码位结构
// 复用同包既有 PBT 辅助（`gen_lines` / `build_text` / `gen_encoding`，来自
// prop_position_offset_test.mbt，**不重定义**）。
//
// 每个生成器都**刻意只构造确定非法的输入**（绝不偶然产生合法帧 / 合法 JSON /
// 合法范围），因此属性「必为 Err 且错误码恰当」是对错误契约的真实校验。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。

// ---------------------------------------------------------------------------
// 字节 / 帧构造辅助（测试本地，ASCII 无损）
// ---------------------------------------------------------------------------

///|
/// ASCII 文本 → `Bytes`（逐字符写出低 8 位；本文件全部构造均为 ASCII）。
fn ec_str_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    arr.push(c.to_int().to_byte())
  }
  Bytes::from_array(arr)
}

///|
/// 以合法 `Content-Length` 头部包裹一段 ASCII 正文，得到一帧字节。正文为 ASCII，
/// 故声明的字节数即正文字符数。供「合法帧 + 非法 JSON 正文」用例。
fn ec_wrap_frame(body : String) -> Bytes {
  let header = "Content-Length: " + body.length().to_string() + "\r\n\r\n"
  ec_str_to_bytes(header + body)
}

// ---------------------------------------------------------------------------
// (1) 畸形 Content-Length 头部帧生成器
// ---------------------------------------------------------------------------

///|
/// 生成一个**确定畸形**的 `Content-Length` 帧字节，覆盖三类畸形：
///   * 缺 `Content-Length` 头部（空头部或仅含其它头部字段）；
///   * `Content-Length` 值非非负整数（字母 / 负号 / 小数 / 空白 / 加号等）；
///   * 正文长度不足（声明字节数大于实际正文字节数）。
/// 三类经 `decode_framed` 均应以 `parse_error_code` 失败。
fn ec_gen_malformed_frame(rng : @infra_pbt.Rng) -> Bytes {
  match rng.next_below(3) {
    // 缺 Content-Length：空头部 / 其它头部字段，随后空行与正文。
    0 => {
      let header = match rng.next_below(4) {
        0 => "" // 空头部块 → "\r\n\r\n{}"
        1 => "X-Custom: 1"
        2 => "Content-Type: application/vscode-jsonrpc; charset=utf-8"
        _ => "Foo: bar"
      }
      ec_str_to_bytes(header + "\r\n\r\n{}")
    }
    // Content-Length 值非非负整数。
    1 => {
      let bad = match rng.next_below(7) {
        0 => "abc"
        1 => "-1"
        2 => "1.5"
        3 => "" // "Content-Length: \r\n..." → 空值
        4 => "0x10"
        5 => "+3"
        _ => "12x"
      }
      ec_str_to_bytes("Content-Length: " + bad + "\r\n\r\n{}")
    }
    // 正文长度不足：声明的字节数大于实际正文字节数。
    _ => {
      let body = match rng.next_below(3) {
        0 => "{}"
        1 => "{\"a\":1}"
        _ => ""
      }
      let declared = body.length() + rng.next_range(1, 10) // 严格大于实际
      ec_str_to_bytes(
        "Content-Length: " + declared.to_string() + "\r\n\r\n" + body,
      )
    }
  }
}

///|
/// 畸形帧字节生成器（封装为 @infra_pbt.Gen）。
fn ec_gen_malformed_frames() -> @infra_pbt.Gen[Bytes] {
  @infra_pbt.Gen::new(fn(rng) { ec_gen_malformed_frame(rng) })
}

// ---------------------------------------------------------------------------
// (2) 非法 JSON 正文生成器
// ---------------------------------------------------------------------------

///|
/// 生成一段**确定无法解析为合法 JSON** 的正文文本（ASCII）。覆盖：未闭合对象 /
/// 数组、未闭合字符串、关键字前缀残缺、结构性垃圾、尾随多余字符、空串等。
/// 经 `decode_message` 均应以 `parse_error_code` 失败。
fn ec_gen_illegal_json(rng : @infra_pbt.Rng) -> String {
  match rng.next_below(6) {
    // 未闭合对象：1..5 个 '{'。
    0 => {
      let n = rng.next_range(1, 5)
      let mut s = ""
      let mut i = 0
      while i < n {
        s = s + "{"
        i = i + 1
      }
      s
    }
    // 未闭合数组：1..5 个 '['。
    1 => {
      let n = rng.next_range(1, 5)
      let mut s = ""
      let mut i = 0
      while i < n {
        s = s + "["
        i = i + 1
      }
      s
    }
    // 未闭合字符串：开引号 + 若干非引号字符（无闭合引号）。
    2 => {
      let pool = ['a', 'b', 'c', ' ', '1', '_']
      let n = rng.next_below(5)
      let mut s = "\""
      let mut i = 0
      while i < n {
        s = s + pool[rng.next_below(pool.length())].to_string()
        i = i + 1
      }
      s
    }
    // 残缺关键字前缀。
    3 =>
      match rng.next_below(5) {
        0 => "tru"
        1 => "fals"
        2 => "nul"
        3 => "t"
        _ => "n"
      }
    // 结构性垃圾 / 尾随多余字符。
    4 =>
      match rng.next_below(8) {
        0 => "}"
        1 => "]"
        2 => ":"
        3 => ","
        4 => "{\"a\":}"
        5 => "[1 2]"
        6 => "{\"a\" 1}"
        _ => "@#$%"
      }
    // 空正文。
    _ => ""
  }
}

///|
/// 非法 JSON 正文生成器（封装为 @infra_pbt.Gen）。
fn ec_gen_illegal_json_bodies() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) { ec_gen_illegal_json(rng) })
}

// ---------------------------------------------------------------------------
// (3) 越界增量变更生成器
// ---------------------------------------------------------------------------

///|
/// 生成一个样本：（文本, 编码, 含越界变更的变更序列）。
///
/// 用 `gen_lines` / `build_text` 造出合法文本与行结构，记其行数 `L`；据此构造
/// **确定越界**的增量变更，覆盖：
///   * start.line ≥ L（行号越界）；
///   * 合法 start，但 end.line ≥ L（行号越界）；
///   * 合法 start，但某行 character 远超该行码元长度（列号越界）。
/// 并以一半概率在越界变更**之前**插入一条合法的全量替换变更（`range = None`），
/// 用以校验「即便前置变更可应用，整体仍以 Err 失败、不返回部分应用结果」。
fn ec_gen_oob_change(
  rng : @infra_pbt.Rng,
) -> (String, PositionEncoding, Array[ContentChange]) {
  let lines = gen_lines(rng)
  let text = build_text(lines)
  let enc = gen_encoding(rng)
  let l = lines.length()
  // 构造一条确定越界的增量变更。行号越界用「远超任何文本行数」的大基数
  // （`l + 100 + ..`）保证：即便前置插入了一条 2 行的全量替换、变更作用于该
  // 全量文本，越界行号仍稳超其行数（不会偶然落入合法范围）。
  let oob : ContentChange = match rng.next_below(3) {
    // start.line 越界。
    0 => {
      let line = l + 100 + rng.next_below(5)
      {
        range: Some({
          start: { line, character: 0 },
          end: { line, character: 0 },
        }),
        text: "x",
      }
    }
    // 合法 start，end.line 越界。
    1 => {
      let end_line = l + 100 + rng.next_below(5)
      {
        range: Some({
          start: { line: 0, character: 0 },
          end: { line: end_line, character: 0 },
        }),
        text: "y",
      }
    }
    // 合法 start，列号远超该行码元长度。
    _ => {
      let li = rng.next_below(l)
      {
        range: Some({
          start: { line: 0, character: 0 },
          end: { line: li, character: 1000000 },
        }),
        text: "z",
      }
    }
  }
  let changes : Array[ContentChange] = []
  // 一半概率前置一条合法全量替换（range = None，恒可应用）。
  if rng.next_bool() {
    changes.push({ range: None, text: "PREFIX-FULL-REPLACE\nsecond line" })
  }
  changes.push(oob)
  (text, enc, changes)
}

///|
/// 越界增量变更样本生成器（封装为 @infra_pbt.Gen）。
fn ec_gen_oob_changes() -> @infra_pbt.Gen[
  (String, PositionEncoding, Array[ContentChange]),
] {
  @infra_pbt.Gen::new(fn(rng) { ec_gen_oob_change(rng) })
}

// ---------------------------------------------------------------------------
// 属性测试（Property 16）—— 三类非法输入各一条 holds_for_all（各默认 100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 16: 畸形 Content-Length 帧返回 parse_error_code
///
/// 对任意由生成器产出的畸形 `Content-Length` 帧，`@lsp_binding.decode_framed`
/// 必以 `Err` 失败，且错误码恰为 `@lsp_binding.parse_error_code`，不 panic、
/// 不产出半成品消息（以 `Err` 而非 `Ok` 体现）。
///
/// **Validates: Requirements 2.3, 11.3**
test "Feature: lsp, Property 16: malformed Content-Length frames fail with parse_error_code" {
  let ok = @infra_pbt.holds_for_all(ec_gen_malformed_frames(), fn(bytes) {
    match @lsp_binding.decode_framed(bytes) {
      Err(e) => e.code == @lsp_binding.parse_error_code
      Ok(_) => false // 畸形帧绝不应解码成功（无半成品消息）
    }
  })
  assert_true(ok)
}

///|
/// Feature: lsp, Property 16: 非法 JSON 正文返回 parse_error_code（裸正文与帧包裹）
///
/// 对任意由生成器产出的非法 JSON 正文：
///   * 直接经 `@lsp_binding.decode_message` 解码裸正文必以 `parse_error_code`
///     失败；
///   * 以合法 `Content-Length` 帧包裹后经 `@lsp_binding.decode_framed` 解码亦以
///     `parse_error_code` 失败（帧切分成功、正文 JSON 解码失败）。
/// 两路径均不 panic、不产出半成品消息。
///
/// **Validates: Requirements 2.3, 11.3**
test "Feature: lsp, Property 16: illegal JSON bodies fail with parse_error_code (raw and framed)" {
  let ok = @infra_pbt.holds_for_all(ec_gen_illegal_json_bodies(), fn(body) {
    let raw_ok = match @lsp_binding.decode_message(ec_str_to_bytes(body)) {
      Err(e) => e.code == @lsp_binding.parse_error_code
      Ok(_) => false
    }
    let framed_ok = match @lsp_binding.decode_framed(ec_wrap_frame(body)) {
      Err(e) => e.code == @lsp_binding.parse_error_code
      Ok(_) => false
    }
    raw_ok && framed_ok
  })
  assert_true(ok)
}

///|
/// Feature: lsp, Property 16: 越界增量变更返回 invalid_params_code 且不部分应用
///
/// 对任意由生成器产出的含越界变更的变更序列，`apply_changes` 必以 `Err` 失败、
/// 错误码恰为 `@lsp_binding.invalid_params_code`，且**返回 `Err` 而非携带半成品
/// 文本的 `Ok`**（纵使前置一条合法全量替换，整体仍失败，前置变更效果不外泄）。
///
/// **Validates: Requirements 3.5, 11.3**
test "Feature: lsp, Property 16: out-of-bounds incremental changes fail with invalid_params_code (no partial apply)" {
  let ok = @infra_pbt.holds_for_all(ec_gen_oob_changes(), fn(sample) {
    let (text, enc, changes) = sample
    match apply_changes(text, changes, enc) {
      Err(e) => e.code == @lsp_binding.invalid_params_code
      Ok(_) => false // 越界变更绝不应返回部分应用结果
    }
  })
  assert_true(ok)
}
