// benches/lsp_bench — 方向五（LSP_Suite）原生基准与 smoke 守护（任务 17.2）。
//
// 本文件实现 LSP_Suite 的五类工作负载基准（每类在递增输入规模上注册
// `@bench.T` 基准块）与对应的 smoke 守护：
//
//   (1) decode/encode 往返吞吐  —— `@binding.encode_message` / `decode_message`
//       对 JSON-RPC 消息做编码→解码往返（params 为 N 项对象，规模递增）。
//   (2) dispatch 路由吞吐        —— `@binding.dispatch` 在一个含多处理器的
//       `Router` 上路由 N 条请求（每次 bench 调用派发一批，规模递增）。
//   (3) 大文档 analyze          —— `@server.analyze` 在含 N 个定义/引用的
//       递增规模 DSL 文档上做静态分析。
//   (4) 增量同步 apply_changes   —— `@server.apply_changes` 顺序应用 N 条等长
//       增量 `ContentChange`（每条替换一行的定值，位置在 UTF-16 编码下稳定）。
//   (5) references / rename     —— 预先 `analyze` 后，`@server.references` /
//       `@server.rename` 在「单键被 N 处引用」的文档上做引用查找与一致改名。
//
// 规模参数（reproducible / R7.x）：
//   - decode/encode  : params 对象项数 N = 8 / 64 / 512
//   - dispatch       : 每次 bench 调用派发的请求条数 N = 16 / 128 / 1024
//   - analyze        : 引用行数 N = 16 / 64 / 256（符号数 = N + 1）
//   - apply_changes  : 增量变更条数 N = 16 / 64 / 256
//   - references     : 单键引用数 N = 16 / 64 / 256（references 结果 = N + 1）
//   - rename         : 单键引用数 N = 16 / 64 / 256（编辑数 = N + 1）
//
// 基准块名称编码「工作负载 + 规模」（如 `analyze_64`、`dispatch_1024`），与
// mini_compiler_bench 同款约定，便于 scripts/ 解析与基线中位数比较。
//
// ── 可复现运行命令（R7.4 / 规模参数记录） ─────────────────────────────
// native 后端运行基准前**必须**先执行：
//     export LIBRARY_PATH=/usr/lib64:/usr/lib
// 再运行原生基准：
//     moon bench benches/lsp_bench --target native
// 或运行 smoke 守护（任一后端）：
//     moon test benches/lsp_bench --target wasm-gc
//     moon test benches/lsp_bench --target js
//     moon test benches/lsp_bench --target native   # 需先 export LIBRARY_PATH
//
// 含机器标识 / 后端目标 / 输入规模 / 计时统计的 JSON / Markdown 工件、基线
// 中位数比较与超容差可审计失败报告，由既有原生基准脚本产出（本包已登记进
// scripts/benchmark_native.ps1 与 scripts/benchmark_smoke.ps1 的基准清单）：
//     pwsh -File scripts/benchmark_native.ps1        -Target native   # 写 benches/results/latest-native.{json,md}
//     pwsh -File scripts/benchmark_native_guard.ps1  -Target native   # 与基线中位数比较，超容差给出回归失败报告（默认容差 25%）
//
// ── 字面 `${` 规避 ───────────────────────────────────────────────────
// DSL 文档含 `${key}` 引用。为规避 JS 后端把源码字面 `${` 误判为模板字符串
// 插值起始（见 src/lsp_server/rename.mbt / demo.mbt 同款约定），文档文本中的
// `${name}` 一律经运行期字符码构造的 `wrap_ref` 拼接，源码中不出现字面 `${`。
//
// _Requirements: 7.1, 7.2, 7.3, 7.4_

// ───────────────────────────── 通用辅助 ───────────────────────────────

///|
/// 在运行期构造 `${name}`（避免源码字面 `${`，三后端一致）。
fn wrap_ref(name : String) -> String {
  let dollar = Int::unsafe_to_char(0x24).to_string() // '$'
  let lbrace = Int::unsafe_to_char(0x7B).to_string() // '{'
  let rbrace = Int::unsafe_to_char(0x7D).to_string() // '}'
  dollar + lbrace + name + rbrace
}

///|
/// 统计字符串的 Unicode 码位个数（`for c in s` 按码位迭代）。
fn char_count(s : String) -> Int {
  let mut c = 0
  for _ in s {
    c = c + 1
  }
  c
}

///|
/// 构造单行范围 `[start_col, end_col)`（同一行 `line`）。
fn make_range(line : Int, start_col : Int, end_col : Int) -> @server.Range {
  { start: { line, character: start_col }, end: { line, character: end_col } }
}

// ───────────────────────── 工作负载生成器 ─────────────────────────────

///|
/// 工作负载 (1)：构造一条 params 为「N 项对象」的 JSON-RPC 请求消息——
/// 对象项数随规模递增，编解码成本随之增长。
fn make_rpc_message(n : Int) -> @binding.JsonRpcMessage {
  let fields : Array[(String, @binding.Json)] = []
  for i in 0..<n {
    fields.push(("k\{i}", @binding.JNum(i.to_string())))
  }
  @binding.Request(
    id=@binding.IdNum(1),
    method_name="workspace/symbol",
    params=@binding.JObj(fields),
  )
}

///|
/// 工作负载 (2)：构造含 8 个处理器（`m0`..`m7`）的 Router；每个处理器对
/// 请求回送一条最小成功响应，对通知不产出回复。
fn make_router() -> @binding.Router {
  let router = @binding.Router::new()
  for i in 0..<8 {
    router.register("m\{i}", fn(msg) {
      match msg {
        @binding.Request(id~, ..) =>
          Some(@binding.Response(id~, result=Some(@binding.JNull), error=None))
        _ => None
      }
    })
  }
  router
}

///|
/// 工作负载 (2)：构造 N 条请求消息，方法在 `m0`..`m7` 间轮转（命中已注册处理器）。
fn make_dispatch_messages(n : Int) -> Array[@binding.JsonRpcMessage] {
  let msgs : Array[@binding.JsonRpcMessage] = []
  for i in 0..<n {
    msgs.push(
      @binding.Request(
        id=@binding.IdNum(i),
        method_name="m\{i % 8}",
        params=@binding.JNull,
      ),
    )
  }
  msgs
}

///|
/// 工作负载 (3)/(5)：构造含「1 个被引用键 `base` + N 行各引用一次 `base`」的
/// DSL 文档。符号数 = N + 1，引用数 = N，故 `references(a, "base")` 结果含
/// N + 1 个定位（定义 + N 处引用）。
fn make_dsl_doc(n : Int) -> @server.TextDocument {
  let nl = "\n"
  let mut s = "base = 0"
  for i in 0..<n {
    s = s + nl + "r\{i} = " + wrap_ref("base")
  }
  { uri: "file:///bench.dsl", text: s }
}

///|
/// 工作负载 (4)：构造增量同步工作负载——文档为 N 行 `k{i} = 0000`，并给出 N 条
/// 等长增量变更，每条把第 i 行的定值 `0000` 替换为 `9999`。等长替换保证后续变更
/// 的位置在 UTF-16 编码下保持稳定（全 ASCII，码位列 = UTF-16 列）。
fn make_sync_workload(
  n : Int,
) -> (String, Array[@server.ContentChange], @server.PositionEncoding) {
  let nl = "\n"
  let mut text = ""
  let changes : Array[@server.ContentChange] = []
  for i in 0..<n {
    let prefix = "k\{i} = "
    let col = char_count(prefix)
    if i > 0 {
      text = text + nl
    }
    text = text + prefix + "0000"
    changes.push({ range: Some(make_range(i, col, col + 4)), text: "9999" })
  }
  (text, changes, @server.Utf16)
}

// ───────────────────────────── 基准块注册 ─────────────────────────────

///|
/// 工作负载 (1)：decode/encode 往返吞吐（R7.x）。
fn bench_decode_encode(b : @bench.T, sizes : Array[Int]) -> Unit {
  for n in sizes {
    let msg = make_rpc_message(n)
    b.bench(name="decode_encode_\{n}", fn() {
      let bytes = @binding.encode_message(msg)
      b.keep(@binding.decode_message(bytes))
    })
  }
}

///|
/// 工作负载 (2)：dispatch 路由吞吐（R7.x）。每次 bench 调用派发整批 N 条请求。
fn bench_dispatch(b : @bench.T, sizes : Array[Int]) -> Unit {
  let router = make_router()
  for n in sizes {
    let msgs = make_dispatch_messages(n)
    b.bench(name="dispatch_\{n}", fn() {
      for m in msgs {
        b.keep(@binding.dispatch(m, router))
      }
    })
  }
}

///|
/// 工作负载 (3)：大文档 analyze（R7.x）。
fn bench_analyze(b : @bench.T, sizes : Array[Int]) -> Unit {
  for n in sizes {
    let doc = make_dsl_doc(n)
    b.bench(name="analyze_\{n}", fn() { b.keep(@server.analyze(doc)) })
  }
}

///|
/// 工作负载 (4)：增量同步 apply_changes（R7.x）。
fn bench_apply_changes(b : @bench.T, sizes : Array[Int]) -> Unit {
  for n in sizes {
    let (text, changes, enc) = make_sync_workload(n)
    b.bench(name="apply_changes_\{n}", fn() {
      b.keep(@server.apply_changes(text, changes, enc))
    })
  }
}

///|
/// 工作负载 (5)：references / rename（R7.x）。预先 `analyze`，仅对引用查找与
/// 一致改名计时。
fn bench_references_rename(b : @bench.T, sizes : Array[Int]) -> Unit {
  for n in sizes {
    let analysis = @server.analyze(make_dsl_doc(n))
    b.bench(name="references_\{n}", fn() {
      b.keep(@server.references(analysis, "base"))
    })
    b.bench(name="rename_\{n}", fn() {
      b.keep(@server.rename(analysis, "base", "newbase"))
    })
  }
}

///|
/// Native benchmark：五类 LSP_Suite 工作负载在递增输入规模上的计时（R7.x）。
/// 基准块名称编码「工作负载 + 规模」，供脚本解析与基线中位数比较。
test "bench: lsp_suite workloads over increasing sizes" (b : @bench.T) {
  // 各工作负载的递增规模参数（见文件头注释）。
  let codec_sizes = [8, 64, 512]
  let dispatch_sizes = [16, 128, 1024]
  let doc_sizes = [16, 64, 256]
  bench_decode_encode(b, codec_sizes)
  bench_dispatch(b, dispatch_sizes)
  bench_analyze(b, doc_sizes)
  bench_apply_changes(b, doc_sizes)
  bench_references_rename(b, doc_sizes)
}

// ───────────────────────────── Smoke 守护 ─────────────────────────────

///|
/// Smoke 守护：协议层 encode/decode 往返。对一条最小 JSON-RPC 通知做
/// `encode_message` 后再 `decode_message`，要求成功解码且与原消息相等，
/// 借此确认对 `@binding` 子包的依赖连通且编解码自洽。
test "smoke: lsp_binding encode/decode round-trip" {
  let msg : @binding.JsonRpcMessage = @binding.Notification(
    method_name="initialized",
    params=@binding.JNull,
  )
  let bytes = @binding.encode_message(msg)
  match @binding.decode_message(bytes) {
    Ok(decoded) => assert_true(decoded == msg)
    Err(_) => assert_true(false)
  }
}

///|
/// Smoke 守护：工作负载 (1) 生成器自洽。对规模 16 的 RPC 消息做编解码往返，
/// 要求成功且与原消息逐位相等。
test "smoke: decode/encode workload round-trips" {
  let msg = make_rpc_message(16)
  let bytes = @binding.encode_message(msg)
  match @binding.decode_message(bytes) {
    Ok(decoded) => assert_true(decoded == msg)
    Err(_) => assert_true(false)
  }
}

///|
/// Smoke 守护：工作负载 (2) dispatch 路由。对命中已注册处理器的请求批做派发，
/// 要求每条都得到一条响应（非 None），借此确认 Router + dispatch 连通。
test "smoke: dispatch workload routes to registered handlers" {
  let router = make_router()
  let msgs = make_dispatch_messages(16)
  for m in msgs {
    match @binding.dispatch(m, router) {
      Some(@binding.Response(..)) => ()
      _ => assert_true(false)
    }
  }
}

///|
/// Smoke 守护：工作负载 (3) 大文档 analyze。对含 1 个定义 + 8 行引用的文档运行
/// `analyze`，要求恰好抽出 9 个符号（base + r0..r7）、8 处引用且无诊断
/// （引用均指向已定义键 base）。
test "smoke: analyze workload projects symbols and references" {
  let doc = make_dsl_doc(8)
  let analysis = @server.analyze(doc)
  assert_true(analysis.symbols.length() == 9)
  assert_true(analysis.references.length() == 8)
  assert_true(analysis.diagnostics.length() == 0)
}

///|
/// Smoke 守护：工作负载 (4) 增量同步。顺序应用 8 条等长增量变更，要求成功且
/// 结果文本逐字符等于「每行定值由 0000 改为 9999」的期望全文。
test "smoke: apply_changes workload applies incremental edits" {
  let (text, changes, enc) = make_sync_workload(8)
  // 期望全文：与生成器同构，仅定值由 0000 替换为 9999。
  let mut expected = ""
  for i in 0..<8 {
    if i > 0 {
      expected = expected + "\n"
    }
    expected = expected + "k\{i} = 9999"
  }
  match @server.apply_changes(text, changes, enc) {
    Ok(updated) => assert_true(updated == expected)
    Err(_) => assert_true(false)
  }
}

///|
/// Smoke 守护：工作负载 (5) references / rename。对「base 被 8 处引用」的文档，
/// `references(a, "base")` 应得 9 个定位（定义 + 8 处引用）；`rename` 产出单
/// 文档项且编辑数同为 9（定义 1 + 引用 8）。
test "smoke: references/rename workload covers all occurrences" {
  let analysis = @server.analyze(make_dsl_doc(8))
  let locs = @server.references(analysis, "base")
  assert_true(locs.length() == 9)
  let edit = @server.rename(analysis, "base", "newbase")
  assert_true(edit.changes.length() == 1)
  let (uri, edits) = edit.changes[0]
  assert_true(uri == "file:///bench.dsl")
  assert_true(edits.length() == 9)
}
