// prop_backend_consistency_test.mbt —— 全方向三后端差分一致性属性测试（任务 18.2）。
//
// 本文件以「黄金快照（golden snapshot）」形式落地 design.md「正确性属性」章节的
// Property 24：三后端差分一致性（横切）。
//
// ── Property 24 的本质与本测试的落地方式 ──────────────────────────────────
// Property 24 要求：*对任意* 方向的同一生成输入集合，在 `wasm-gc` / `js` /
// `native` 三后端上运行同一测试套件应产生**逐一致**的输出（含快照）；任一后端
// 分歧即判定为构建失败。该性质由 CI 三后端矩阵（`matrix.backend =
// [wasm-gc, js, native]`，任务 18.1）承载。
//
// 本测试在一个确定性纯函数 `backend_digest` 中，用 @infra_pbt 的种子驱动随机源
// `Rng`（xorshift64，仅移位/异或，三后端逐位一致）生成一批跨方向输入，并依次
// 调用各方向的核心 API：
//   * @infra_pbt.Rng           —— 64 位伪随机序列（核心：UInt64 位运算一致性）
//   * @parser_combinator       —— many/pchar 计数（解析器组合子确定性）
//   * @regex_engine            —— parse/print 往返 + NFA/DFA 差分一致性
//   * @serialization           —— protobuf varint 编码（64 位 wire format 一致性）
//   * @build_tool              —— 拓扑排序（图调度确定性）
//   * @dst                     —— 确定性仿真调度（同种子 → 同轨迹）
//   * release_aggregate        —— 全方向发布就绪聚合（本包自身）
// 把这些输出折叠为单行规范摘要字符串，再用 `inspect(..., content=...)` 钉死
// 黄金值。由于该快照在 CI 三后端矩阵下逐一运行，任一后端的整数 / 字符串 / 结构
// 渲染语义分歧都会使快照失配 → 该后端 CI run 失败，从而把 Property 24 落为
// **可执行的差分门禁见证**。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 小工具（格式化 / 生成）—— 纯函数，三后端逐位一致
// ---------------------------------------------------------------------------

///|
/// 单个十六进制数字（小写）。仅用移位无关的整数比较与加法，三后端一致。
fn hex_digit(d : Int) -> Char {
  if d < 10 {
    (d + '0'.to_int()).unsafe_to_char()
  } else {
    (d - 10 + 'a'.to_int()).unsafe_to_char()
  }
}

///|
/// 把字节序列渲染为小写十六进制字符串（每字节 2 位，高位在前）。
///
/// 用于把 @serialization.encode 产出的 wire format 字节做稳定快照，
/// 任一后端字节级分歧都会反映为不同的十六进制串。
fn bytes_hex(b : Bytes) -> String {
  let mut s = ""
  let mut i = 0
  while i < b.length() {
    let v = b[i].to_int()
    s = s + "\{hex_digit(v / 16)}\{hex_digit(v % 16)}"
    i = i + 1
  }
  s
}

///|
/// 以逗号连接构建目标名清单（拓扑序的稳定文本形式）。
fn join_targets(ts : Array[@build_tool.Target]) -> String {
  let mut s = ""
  let mut i = 0
  while i < ts.length() {
    if i > 0 {
      s = s + ","
    }
    s = s + ts[i].name
    i = i + 1
  }
  s
}

///|
/// 以分隔符 " | " 连接摘要行。
fn join_lines(lines : Array[String]) -> String {
  let mut s = ""
  let mut i = 0
  while i < lines.length() {
    if i > 0 {
      s = s + " | "
    }
    s = s + lines[i]
    i = i + 1
  }
  s
}

///|
/// 用种子随机源生成一个由 'a'/'b'/'c'/'d' 构成、长度 `[0, maxlen]` 的字符串。
///
/// 该字符集恰好覆盖示例正则 `a(b|c)*d` 的字母表，使生成输入既能命中匹配也能
/// 命中失配，充分检验三后端下正则匹配（NFA/DFA）的一致性。
fn gen_abcd(rng : @infra_pbt.Rng, maxlen : Int) -> String {
  let alphabet = ['a', 'b', 'c', 'd']
  let len = rng.next_below(maxlen + 1)
  let mut s = ""
  let mut k = 0
  while k < len {
    s = s + "\{alphabet[rng.next_below(4)]}"
    k = k + 1
  }
  s
}

// ---------------------------------------------------------------------------
// 跨方向确定性摘要（cross-direction deterministic digest）
// ---------------------------------------------------------------------------

///|
/// 给定种子，跨全部方向计算一组确定性输出并折叠为单行规范摘要字符串。
///
/// 整个过程不含浮点、不含非确定性来源（无并发、无系统时钟、无哈希遍历序），
/// 仅依赖 MoonBit 在三后端上一致的整数（Int 32 位回绕 / UInt64 64 位）与字符串
/// 语义，因此**任意后端都应产生逐位相同的摘要**。这是 Property 24 的可执行见证。
fn backend_digest(seed : UInt64) -> String {
  let rng = @infra_pbt.rng_new(seed)
  let lines : Array[String] = []

  // 1) @infra_pbt.Rng —— 64 位伪随机序列（xorshift64，三后端位运算一致）。
  let r0 = rng.next()
  let r1 = rng.next()
  let r2 = rng.next()
  let r3 = rng.next()
  lines.push("rng=\{r0},\{r1},\{r2},\{r3}")

  // 2) @parser_combinator —— many(pchar('a')) 对生成串计数前缀 'a' 的个数。
  let ps = gen_abcd(rng, 6)
  let pc = match
    @parser_combinator.many(@parser_combinator.pchar('a')).parse_string(ps) {
    Ok(arr, rest) => "len=\{arr.length()},eof=\{rest.is_eof()}"
    Fail(_, ..) => "fail"
  }
  lines.push("pc[\{ps}]=\{pc}")

  // 3) @regex_engine —— 解析示例正则并打印（往返），再对生成串做匹配 +
  //    NFA/DFA 差分一致性校验（Property 5 的横切复用）。
  let re = match @regex_engine.parse_regex("a(b|c)*d") {
    Ok(r) => r
    Err(_) => @regex_engine.Regex::Char('?')
  }
  lines.push("re-print=\{@regex_engine.print_regex(re)}")
  let nfa = @regex_engine.build_nfa(re)
  let dfa = @regex_engine.to_dfa(nfa)
  let mut matches = ""
  let mut j = 0
  while j < 5 {
    let s = gen_abcd(rng, 5)
    let m = @regex_engine.is_match(re, s)
    let agree = nfa.find(s) == dfa.find(s)
    matches = matches + "(\{s}:\{m}:\{agree})"
    j = j + 1
  }
  lines.push("re-match=\{matches}")

  // 4) @serialization —— 用 64 位随机值构造消息并编码为 protobuf wire format。
  let v1 = rng.next()
  let v2 = rng.next()
  let msg = @serialization.Message::from_fields([
    @serialization.FieldEntry::new(1, @serialization.FieldValue::varint(v1)),
    @serialization.FieldEntry::new(2, @serialization.FieldValue::varint(v2)),
  ])
  let enc = @serialization.encode(msg)
  lines.push("ser-len=\{enc.length()},ser-hex=\{bytes_hex(enc)}")

  // 5) @build_tool —— 在固定 DAG 上做拓扑排序（复用 @directed.topo_sort）。
  let a = @build_tool.Target::new("a")
  let b = @build_tool.Target::new("b")
  let c = @build_tool.Target::new("c")
  let d = @build_tool.Target::new("d")
  let graph = @build_tool.BuildGraph::new([a, b, c, d], [
    (a, b),
    (a, c),
    (b, d),
    (c, d),
  ])
  let topo = match @build_tool.topo_order(graph) {
    Ok(order) => join_targets(order)
    Err(_) => "cycle"
  }
  lines.push("build-topo=\{topo}")

  // 6) @dst —— 同种子确定性仿真：固定任务集，输出轨迹长度与终态。
  let scenario = @dst.Scenario::new(
    [@dst.Task::new(0, "t0"), @dst.Task::new(1, "t1"), @dst.Task::new(2, "t2")],
    [],
    8,
  )
  let sim = @dst.run(seed, scenario)
  lines.push("dst-trace=\{sim.trace.length()},dst-status=\{sim.status}")

  // 7) release_aggregate（本包）—— 全方向发布就绪聚合（全绿门禁 → 整体就绪）。
  let report = aggregate_suite(uniform_suite_gates(gates_of(true)))
  lines.push(
    "agg-count=\{report.directions.length()},agg-ready=\{report.release_ready}",
  )
  join_lines(lines)
}

// ---------------------------------------------------------------------------
// Property 24：三后端差分一致性（横切）—— 黄金快照
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 24: 三后端差分一致性（横切）
///
/// 用固定种子跨全部方向计算确定性摘要，并以 `inspect` 钉死黄金值。该快照在
/// CI 三后端矩阵（wasm-gc / js / native）下逐一运行：任一后端的整数 / 字符串 /
/// 结构渲染语义分歧都会使快照失配，从而令该后端构建失败——这正是 Property 24
/// 「任一后端分歧即构建失败」的可执行差分门禁见证。
///
/// **Validates: Requirements 1.10, 2.9, 3.8, 4.8, 6.8, 8.7, 9.9, 11.1**
test "Feature: moonbit-infra-suite, Property 24: cross-backend differential consistency golden snapshot" {
  inspect(
    backend_digest(0x12345678),
    content=(
      #|rng=325431077887975636,18232491228267729045,10070706077742329972,240325013275281556 | pc[cca]=len=0,eof=false | re-print=a(b|c)*d | re-match=(bb:false:true)(add:true:true)(acadb:true:true)(d:false:true)(dcb:false:true) | ser-len=20,ser-hex=08e49cbdd2c6c6deef6610f893d3dbaeb38dd601 | build-topo=a,b,c,d | dst-trace=6,dst-status=Completed | agg-count=10,agg-ready=true
    ),
  )
}

///|
/// Feature: moonbit-infra-suite, Property 24: 三后端差分一致性（确定性不变量）
///
/// 同种子两次计算跨方向摘要必逐位相等（确定性 / 可重放）。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，对一批随机种子穷举校验（默认 100 次迭代）。
/// 确定性是「同一测试在三后端产生相同输出」的前提：若摘要对同种子都不可重放，
/// 则跨后端一致性无从谈起。
///
/// **Validates: Requirements 1.10, 2.9, 3.8, 4.8, 6.8, 8.7, 9.9, 11.1**
test "Feature: moonbit-infra-suite, Property 24: cross-direction digest is deterministic for any seed" {
  let ok = @infra_pbt.holds_for_all(@infra_pbt.gen_int_range(1, 1_000_000), fn(
    seed,
  ) {
    let s = seed.to_uint64()
    backend_digest(s) == backend_digest(s)
  })
  assert_true(ok)
}
