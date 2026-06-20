// lsp_ext_prop_test.mbt —— LSP 增强（成帧 + 增量同步 + JSON-RPC 结构校验）属性测试
// （旗舰深化，任务 11.3 旁路新增；仅新增测试，不改既有签名与测试）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 10「R10 成帧与增量同步」，拆解为四条独立属性，每条复用共享 PBT 包
// @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认 `iters=100`，满足每条
// 属性 ≥100 次迭代基线）。纯函数、无 IO，三后端（wasm-gc / js / native）一致。
//
//   * 属性 1（成帧往返，AC3 / Requirement 10.3）：
//       对任意随机 body，`decode_frame(encode_frame(body)) == Ok((body, ""))`
//       （还原 body 且剩余段为空）。
//   * 属性 2（`\r\n` / `\n` 头兼容，AC2 / Requirement 10.2）：
//       对任意随机 body，手工以「码位数 N」构造 `\r\n\r\n` 与 `\n\n` 两种头部的帧，
//       二者 `decode_frame` 均得 `Ok((body, ..))` 且解出的 body 一致。
//   * 属性 3（增量同步 == 全量 apply_changes，AC4 / Requirement 10.4）：
//       对任意随机文档 + 随机单条合法 `ContentChange`（Full 或行内合法范围），
//       `apply_incremental(doc, change, enc) == apply_changes(doc, [change], enc)`。
//   * 属性 4（非法 JSON-RPC 结构返回错误，AC6 / Requirement 10.6）：
//       构造若干合法（request/notification/response）与非法 Json，
//       `validate_jsonrpc` 对合法者返回 `Ok`、对非法者返回 `Err`。
//
// ── 复用与边界说明 ──────────────────────────────────────────────────────────
// 本文件为黑盒测试，仅依赖 lsp_server 的公开 API（`encode_frame` / `decode_frame`
// / `apply_incremental` / `apply_changes` / `validate_jsonrpc` / `ContentChange`
// / `Range` / `Position` / `PositionEncoding`）与 @lsp_binding 的公开 `Json`
// 构造子（`JObj` / `JStr` / `JNum` / `JArr` / `JNull` / `JBool`）。
// 文档 / 行结构 / 编码 / 列号换算等生成器辅助复用同包既有 PBT helper
// （`gen_lines` / `build_text` / `char_col` / `gen_encoding` / `gen_code_point`
// / `code_point_pool`，来自 prop_position_offset_test.mbt），**不重定义**。
// 本文件新增的局部 helper 一律以 `lx_` 前缀命名以避免与既有定义冲突，且文本构建
// 统一使用 `Array[String]::join`（禁止循环内字符串 `+` 的 O(n²) 拼接）。

// ---------------------------------------------------------------------------
// 共享局部 helper（lx_ 前缀，避免与既有 PBT helper 重名）
// ---------------------------------------------------------------------------

///|
/// 由一段 Unicode 码位序列重建字符串（用 `Array[String]::join`，避免循环内 `+`）。
fn lx_cps_to_string(cps : Array[Int]) -> String {
  let parts : Array[String] = []
  for cp in cps {
    parts.push(cp.unsafe_to_char().to_string())
  }
  parts.join("")
}

// ---------------------------------------------------------------------------
// 属性 1 / 2 共用：成帧 body 生成器
// ---------------------------------------------------------------------------

///|
/// 成帧 body 的码位池：覆盖字母 / 数字 / 空格 / 少量符号，外加换行 `\n`、冒号 `:`
/// （body 位于头体分隔之后，含 `:` / `\n` 可校验「body 不被误当作头部解析」），
/// 以及 CJK（中）与 emoji（😀，BMP 外、UTF-16 代理对、UTF-8 四字节）以覆盖多码元
/// 字符在「按码位度量 / 按码位切割」下仍能严格往返。
let lx_frame_body_pool : Array[Int] = [
  0x61, // 'a'
   0x62, // 'b'
   0x5A, // 'Z'
   0x30, // '0'
   0x39, // '9'
   0x20, // ' '
   0x3D, // '='
   0x2D, // '-'
   0x3A, // ':'
   0x0A, // '\n'
   0x4E2D, // '中'
   0x1F600, // '😀'
]

///|
/// 生成一个成帧样本 `(body, n)`：body 为 0..11 个码位拼成的字符串，n 为其码位数
/// （即 `encode_frame` 写入的 Content-Length 度量口径，由生成时直接计数得到，
/// 无需触碰任何私有内部工具）。
fn lx_gen_body_with_n(rng : @infra_pbt.Rng) -> (String, Int) {
  let len = rng.next_below(12) // 0..11 码位
  let cps : Array[Int] = []
  let mut k = 0
  while k < len {
    cps.push(lx_frame_body_pool[rng.next_below(lx_frame_body_pool.length())])
    k = k + 1
  }
  (lx_cps_to_string(cps), cps.length())
}

///|
/// 成帧样本生成器（封装为 @infra_pbt.Gen）。
fn lx_gen_frame_samples() -> @infra_pbt.Gen[(String, Int)] {
  @infra_pbt.Gen::new(fn(rng) { lx_gen_body_with_n(rng) })
}

// ---------------------------------------------------------------------------
// 属性 1：成帧往返（AC3 / Requirement 10.3）
// ---------------------------------------------------------------------------

///|
/// Feature: production-hardening, Property 10: frame encode/decode round-trips body exactly
///
/// 对任意随机 body：`decode_frame(encode_frame(body))` 必为 `Ok((body, ""))`——
/// 即解出的 body 与原 body 逐字符相等，且剩余段 rest 为空串（单帧无尾随数据）。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 10.3**
test "Feature: production-hardening, Property 10: frame encode/decode round-trips the body exactly" {
  let ok = @infra_pbt.holds_for_all(lx_gen_frame_samples(), fn(sample) {
    let (body, _) = sample
    match decode_frame(encode_frame(body)) {
      // 往返还原 body，且无剩余尾随数据。
      Ok((decoded, rest)) => decoded == body && rest == ""
      Err(_) => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// 属性 2：`\r\n` / `\n` 头兼容（AC2 / Requirement 10.2）
// ---------------------------------------------------------------------------

///|
/// Feature: production-hardening, Property 10: CRLF and LF header separators both decode equally
///
/// 对任意随机 body，以与 `encode_frame` 相同的「码位数 N」手工构造两种帧：
///   * 规范 `\r\n\r\n` 头：`"Content-Length: N\r\n\r\n" + body`；
///   * 宽松 `\n\n` 头：    `"Content-Length: N\n\n" + body`。
/// 断言二者 `decode_frame` 均为 `Ok((body, ..))` 且解出的 body 彼此一致并等于原
/// body（头部分隔符兼容性，鲁棒应对不同客户端换行行为）。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 10.2**
test "Feature: production-hardening, Property 10: CRLF and LF header separators decode to the same body" {
  let ok = @infra_pbt.holds_for_all(lx_gen_frame_samples(), fn(sample) {
    let (body, n) = sample
    // 用 Array join 拼接帧（非循环、避免 O(n²) 字符串 +）。
    let crlf_frame = ["Content-Length: ", n.to_string(), "\r\n\r\n", body].join(
      "",
    )
    let lf_frame = ["Content-Length: ", n.to_string(), "\n\n", body].join("")
    match (decode_frame(crlf_frame), decode_frame(lf_frame)) {
      // 两种头部均成功解码，且 body 一致并等于原 body。
      (Ok((b1, _)), Ok((b2, _))) => b1 == body && b2 == body && b1 == b2
      _ => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// 属性 3：增量同步 == 全量 apply_changes（AC4 / Requirement 10.4）
// ---------------------------------------------------------------------------

///|
/// 生成 0..5 个码位的替换文本（取自 `code_point_pool`，不含 '\n'，保持行结构）。
fn lx_gen_repl_text(rng : @infra_pbt.Rng) -> String {
  let len = rng.next_below(6) // 0..5 码位
  let cps : Array[Int] = []
  let mut k = 0
  while k < len {
    cps.push(gen_code_point(rng))
    k = k + 1
  }
  lx_cps_to_string(cps)
}

///|
/// 生成一个增量同步样本 `(doc, enc, change)`：
///   * 1/4 概率为 Full（`range = None`）：整篇替换为随机文本；
///   * 否则为 Incremental：在随机一行内取两个**码位边界**索引排序为 `[ci_start,
///     ci_end)`，经 `char_col` 在 `enc` 下换算为合法列号，构成单行合法范围，
///     替换为随机文本。
/// 行结构与列号换算复用既有 helper，保证范围恰落在码位边界（不会切在多码元字符
/// 中间），故对合法范围 `apply_incremental` 与 `apply_changes` 均应成功。
fn lx_gen_single_change_sample(
  rng : @infra_pbt.Rng,
) -> (String, PositionEncoding, ContentChange) {
  let lines = gen_lines(rng)
  let doc = build_text(lines)
  let enc = gen_encoding(rng)
  // 1/4 概率走 Full 全量替换分支。
  if rng.next_below(4) == 0 {
    return (doc, enc, { range: None, text: lx_gen_repl_text(rng) })
  }
  // Incremental：选一行，行内两个码位边界索引。
  let li = rng.next_below(lines.length())
  let line = lines[li]
  let m = line.length()
  let a = rng.next_below(m + 1)
  let b = rng.next_below(m + 1)
  let ci_start = if a <= b { a } else { b }
  let ci_end = if a <= b { b } else { a }
  let start_col = char_col(line, enc, ci_start)
  let end_col = char_col(line, enc, ci_end)
  let range : Range = {
    start: { line: li, character: start_col },
    end: { line: li, character: end_col },
  }
  (doc, enc, { range: Some(range), text: lx_gen_repl_text(rng) })
}

///|
/// 增量同步样本生成器（封装为 @infra_pbt.Gen）。
fn lx_gen_single_change_samples() -> @infra_pbt.Gen[
  (String, PositionEncoding, ContentChange),
] {
  @infra_pbt.Gen::new(fn(rng) { lx_gen_single_change_sample(rng) })
}

///|
/// Feature: production-hardening, Property 10: single-change incremental sync equals full apply_changes
///
/// 对任意随机文档 + 随机单条合法 `ContentChange`（Full 或行内合法范围）与编码：
///   `apply_incremental(doc, change, enc) == apply_changes(doc, [change], enc)`。
/// 二者对同一单条变更走完全相同的换算 / 切片逻辑，故 `Result`（含 `Ok` 文本与
/// `Err` 错误对象）应逐字段相等（`Result` / `String` / `RpcError` 均 `derive(Eq)`）。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 10.4**
test "Feature: production-hardening, Property 10: incremental sync of a single change equals full apply_changes" {
  let ok = @infra_pbt.holds_for_all(lx_gen_single_change_samples(), fn(sample) {
    let (doc, enc, change) = sample
    apply_incremental(doc, change, enc) == apply_changes(doc, [change], enc)
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// 属性 4：非法 JSON-RPC 结构返回错误（AC6 / Requirement 10.6）
// ---------------------------------------------------------------------------

///|
/// JSON-RPC method 名候选池（随机化部分字段，避免平凡样本）。
let lx_method_pool : Array[String] = [
  "initialize", "textDocument/didChange", "textDocument/completion", "shutdown",
  "$/cancelRequest", "m",
]

///|
/// 随机选一个 method 名。
fn lx_gen_method(rng : @infra_pbt.Rng) -> String {
  lx_method_pool[rng.next_below(lx_method_pool.length())]
}

///|
/// 随机生成一个**合法** id（string / number / null 三选一）。
fn lx_gen_valid_id(rng : @infra_pbt.Rng) -> @lsp_binding.Json {
  match rng.next_below(3) {
    0 => @lsp_binding.JNum(rng.next_range(0, 9999).to_string())
    1 => @lsp_binding.JStr(["id-", rng.next_range(0, 999).to_string()].join(""))
    _ => @lsp_binding.JNull
  }
}

///|
/// 随机生成一个**非法** id（bool / array / object 三选一，均非 string/number/null）。
fn lx_gen_invalid_id(rng : @infra_pbt.Rng) -> @lsp_binding.Json {
  match rng.next_below(3) {
    0 => @lsp_binding.JBool(rng.next_bool())
    1 => @lsp_binding.JArr([@lsp_binding.JNum("1")])
    _ => @lsp_binding.JObj([("k", @lsp_binding.JStr("v"))])
  }
}

///|
/// 随机生成一个非对象 Json（顶层非 `JObj`，应判 `ParseErr`）。
fn lx_gen_non_object(rng : @infra_pbt.Rng) -> @lsp_binding.Json {
  match rng.next_below(5) {
    0 => @lsp_binding.JNull
    1 => @lsp_binding.JBool(rng.next_bool())
    2 => @lsp_binding.JNum(rng.next_range(0, 99).to_string())
    3 => @lsp_binding.JStr("not-an-object")
    _ => @lsp_binding.JArr([@lsp_binding.JStr("2.0")])
  }
}

///|
/// 生成一个 JSON-RPC 校验样本 `(json, expect_valid)`：覆盖合法（请求 / 通知 /
/// 响应）与多类非法（非对象 / 缺 jsonrpc / jsonrpc 值错 / 响应 result+error 并存 /
/// 响应二者皆缺 / method 非字符串 / 请求 id 类型非法 / 仅含 jsonrpc）结构，
/// 并随机化 method、id 等字段。
fn lx_gen_jsonrpc_sample(rng : @infra_pbt.Rng) -> (@lsp_binding.Json, Bool) {
  let v2 = @lsp_binding.JStr("2.0")
  match rng.next_below(12) {
    // ── 合法形态 ──────────────────────────────────────────────────────────
    // 0：合法请求（jsonrpc + method + 合法 id）。
    0 =>
      (
        @lsp_binding.JObj([
          ("jsonrpc", v2),
          ("method", @lsp_binding.JStr(lx_gen_method(rng))),
          ("id", lx_gen_valid_id(rng)),
        ]),
        true,
      )
    // 1：合法通知（jsonrpc + method，无 id）。
    1 =>
      (
        @lsp_binding.JObj([
          ("jsonrpc", v2),
          ("method", @lsp_binding.JStr(lx_gen_method(rng))),
        ]),
        true,
      )
    // 2：合法响应（jsonrpc + id + result，且无 error）。
    2 =>
      (
        @lsp_binding.JObj([
          ("jsonrpc", v2),
          ("id", lx_gen_valid_id(rng)),
          ("result", @lsp_binding.JNull),
        ]),
        true,
      )
    // 3：合法响应（jsonrpc + id + error，且无 result）。
    3 =>
      (
        @lsp_binding.JObj([
          ("jsonrpc", v2),
          ("id", lx_gen_valid_id(rng)),
          (
            "error",
            @lsp_binding.JObj([
              ("code", @lsp_binding.JNum("-32600")),
              ("message", @lsp_binding.JStr("err")),
            ]),
          ),
        ]),
        true,
      )
    // ── 非法形态 ──────────────────────────────────────────────────────────
    // 4：顶层非对象 → ParseErr。
    4 => (lx_gen_non_object(rng), false)
    // 5：缺 jsonrpc 字段 → InvalidRequest。
    5 =>
      (
        @lsp_binding.JObj([
          ("method", @lsp_binding.JStr(lx_gen_method(rng))),
          ("id", lx_gen_valid_id(rng)),
        ]),
        false,
      )
    // 6：jsonrpc 值错误（非 "2.0"）→ InvalidRequest。
    6 =>
      (
        @lsp_binding.JObj([
          ("jsonrpc", @lsp_binding.JStr("1.0")),
          ("method", @lsp_binding.JStr(lx_gen_method(rng))),
          ("id", lx_gen_valid_id(rng)),
        ]),
        false,
      )
    // 7：响应中 result 与 error 并存 → InvalidRequest。
    7 =>
      (
        @lsp_binding.JObj([
          ("jsonrpc", v2),
          ("id", lx_gen_valid_id(rng)),
          ("result", @lsp_binding.JNull),
          ("error", @lsp_binding.JObj([("code", @lsp_binding.JNum("-32000"))])),
        ]),
        false,
      )
    // 8：响应中 result 与 error 皆缺 → InvalidRequest。
    8 =>
      (
        @lsp_binding.JObj([("jsonrpc", v2), ("id", lx_gen_valid_id(rng))]),
        false,
      )
    // 9：含 method 但 method 非字符串 → InvalidRequest。
    9 =>
      (
        @lsp_binding.JObj([
          ("jsonrpc", v2),
          ("method", @lsp_binding.JNum(rng.next_range(0, 9).to_string())),
          ("id", lx_gen_valid_id(rng)),
        ]),
        false,
      )
    // 10：请求 id 类型非法（bool/array/object）→ InvalidRequest。
    10 =>
      (
        @lsp_binding.JObj([
          ("jsonrpc", v2),
          ("method", @lsp_binding.JStr(lx_gen_method(rng))),
          ("id", lx_gen_invalid_id(rng)),
        ]),
        false,
      )
    // 11：仅含 jsonrpc（既无 method 又无 id）→ 落入响应分支且缺 id → InvalidRequest。
    _ => (@lsp_binding.JObj([("jsonrpc", v2)]), false)
  }
}

///|
/// JSON-RPC 校验样本生成器（封装为 @infra_pbt.Gen）。
fn lx_gen_jsonrpc_samples() -> @infra_pbt.Gen[(@lsp_binding.Json, Bool)] {
  @infra_pbt.Gen::new(fn(rng) { lx_gen_jsonrpc_sample(rng) })
}

///|
/// Feature: production-hardening, Property 10: JSON-RPC structural validation accepts valid and rejects invalid
///
/// 对任意由生成器产出的 `(json, expect_valid)`：`validate_jsonrpc(json)` 当且仅当
/// `expect_valid` 为真时返回 `Ok`，否则返回 `Err`（非法结构必产出结构化错误对象，
/// 不 panic / 不 abort）。覆盖合法请求 / 通知 / 响应与八类非法结构。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 10.6**
test "Feature: production-hardening, Property 10: validate_jsonrpc accepts well-formed and rejects malformed messages" {
  let ok = @infra_pbt.holds_for_all(lx_gen_jsonrpc_samples(), fn(sample) {
    let (json, expect_valid) = sample
    match validate_jsonrpc(json) {
      Ok(_) => expect_valid
      Err(_) => !expect_valid
    }
  })
  assert_true(ok)
}
