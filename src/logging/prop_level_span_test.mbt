// prop_level_span_test.mbt —— 级别过滤与 span/trace 不变量属性测试（task 10.3）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// 两条不变量，复用共享 PBT 包 @infra_pbt 的种子驱动随机源 `Rng` 与不变量断言
// 模板 `holds_for_all`（默认迭代 100 次，满足 ≥100 迭代基线，三后端逐位一致、
// 可重放）。每条属性谓词进入时调用 `reset_logger()` 隔离进程级全局状态。
//
//   Feature: moonbit-infra-suite, Property 16: 日志级别阈值过滤
//   --------------------------------------------------------------------
//   *对任意* 事件序列与配置阈值：级别 rank ≥ 阈值 rank 的事件被保留且保持
//   原序，级别低于阈值的事件被丢弃（Requirement 7.2）。
//
//   Feature: moonbit-infra-suite, Property 17: Span 树与 trace 上下文传播不变量
//   --------------------------------------------------------------------
//   *对任意* 嵌套 span 序列：根 span 无父；嵌套 span 的父为其外层 span（形成
//   span 树）；激活 span 内产生的事件被标注该 span 与当前 trace 上下文标识；
//   且跨异步任务边界（with_context）时子任务保留父任务 trace 标识、子 span
//   挂接父任务激活 span，退出子任务后父任务状态被原样还原
//   （Requirement 7.3 / 7.4 / 7.6）。
//
// 命名约定：本文件所有本地辅助使用独立前缀 `ls_` / `gen_ls_` / `prop_ls_`，
// 与同包 prop_roundtrip_test.mbt 的 `rt_` / `gen_rt_` 前缀互不冲突。
//
// 断言模板使用模式：每条属性以「`Gen[Bool]` 的 sample 函数内运行一次完整、
// 自隔离（先 reset_logger）的场景并返回不变量是否成立」表达，再交由
// `holds_for_all(gen, fn(ok) { ok })` 迭代 100 次。如此每次迭代都从共享随机源
// 取得新的（确定性）输入，且彼此互不串扰全局日志状态。

// ---------------------------------------------------------------------------
// 生成器（generator）—— 随机日志级别
// ---------------------------------------------------------------------------

///|
/// 随机日志级别生成器：等概率产出 Trace / Debug / Info / Warn / Error 之一。
fn gen_ls_level(rng : @infra_pbt.Rng) -> Level {
  match rng.next_below(5) {
    0 => Trace
    1 => Debug
    2 => Info
    3 => Warn
    _ => Error
  }
}

// ---------------------------------------------------------------------------
// Property 16：日志级别阈值过滤 —— 谓词实现
// ---------------------------------------------------------------------------

///|
/// 单次场景：随机阈值 + 随机级别事件序列，断言级别阈值过滤不变量。
///
/// 步骤：
///   1. 重置日志运行时（隔离全局状态），随机选定阈值并配置；
///   2. 生成 0~12 个随机级别事件，每个事件带唯一序号字段 `seq`（= 其原始下标）；
///   3. 计算「应被保留」的下标集合 expected（级别 rank ≥ 阈值 rank，保持原序）；
///   4. 依次 `log` 全部事件；
///   5. 断言 `captured_events()`：
///      * 数量等于 expected 数量（低于阈值者被丢弃）；
///      * 每个被保留事件的级别满足阈值（`is_enabled`）；
///      * 被保留事件的 `seq` 序号严格按 expected 顺序排列（保持原序）；
///      * 被保留事件的级别与原序列对应下标一致。
fn prop_ls_level_filter(rng : @infra_pbt.Rng) -> Bool {
  reset_logger()
  let threshold = gen_ls_level(rng)
  set_threshold(threshold)
  // 随机长度（含 0）事件级别序列。
  let n = rng.next_range(0, 12)
  let levels : Array[Level] = []
  for _i in 0..<n {
    levels.push(gen_ls_level(rng))
  }
  // 预期保留的原始下标（保持原序）。
  let expected : Array[Int] = []
  for i in 0..<levels.length() {
    if levels[i].rank() >= threshold.rank() {
      expected.push(i)
    }
  }
  // 依序记录每个事件，携带唯一序号字段以校验「保持原序」。
  for i in 0..<levels.length() {
    log(levels[i], { "seq": VInt(i.to_int64()) })
  }
  let events = captured_events()
  // 数量：低于阈值者被丢弃。
  if events.length() != expected.length() {
    return false
  }
  for j in 0..<events.length() {
    let e = events[j]
    // 被保留事件级别必须不低于阈值。
    if !e.level.is_enabled(threshold) {
      return false
    }
    // 保持原序：第 j 个被保留事件的 seq 应等于 expected[j]。
    match e.fields.get("seq") {
      Some(VInt(v)) => if v != expected[j].to_int64() { return false }
      _ => return false
    }
    // 被保留事件的级别应与原序列对应下标一致。
    if e.level != levels[expected[j]] {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Property 17：Span 树与 trace 上下文传播不变量 —— 谓词实现
// ---------------------------------------------------------------------------

///|
/// 单次场景（span 树 + 事件上下文标注）：随机深度地连续进入嵌套 span，断言
/// span 树结构与激活 span 内事件标注不变量。
///
/// 断言：
///   * 根 span（首个进入）`parent == None`；
///   * 其后每个嵌套 span 的 `parent` 等于其外层（前一个）span 的 id（span 树）；
///   * 在每个 span 激活期间产生的事件，其字段被标注当前（最内层）span id 与
///     当前 trace id（Requirement 7.4）。
/// 场景结束按逆序退出全部 span，恢复运行时栈。
fn prop_ls_span_tree(rng : @infra_pbt.Rng) -> Bool {
  reset_logger()
  let trace = begin_trace()
  let depth = rng.next_range(1, 6)
  let spans : Array[Span] = []
  let mut prev : SpanId? = None
  for d in 0..<depth {
    let s = enter_span("s\{d}")
    if d == 0 {
      // 根 span 无父。
      if !(s.parent is None) {
        return false
      }
      // 嵌套 span 的父为外层 span。
    } else if s.parent != prev {
      return false
    }
    // 激活 span 内事件标注最内层 span 与当前 trace。
    log(Level::Info, {})
    let ev = captured_events()
    let last = ev[ev.length() - 1]
    match last.fields.get("span") {
      Some(VInt(v)) => if v != s.id.value { return false }
      _ => return false
    }
    match last.fields.get("trace") {
      Some(VInt(v)) => if v != trace.value { return false }
      _ => return false
    }
    prev = Some(s.id)
    spans.push(s)
  }
  // 逆序退出，恢复运行时状态。
  for d = spans.length() - 1; d >= 0; d = d - 1 {
    exit_span(spans[d])
  }
  true
}

///|
/// 单次场景（跨异步任务边界 trace 上下文传播）：在一组激活 span 之上捕获上下文，
/// 派生子上下文并在 `with_context` 下运行子任务，断言传播与还原不变量。
///
/// 断言（Requirement 7.6 及配套 7.3 / 7.4）：
///   * 子上下文保留父任务 trace 标识（`child.trace == parent_trace`）；
///   * 在 `with_context` 内 `current_trace()` 仍为父 trace（跨边界保留）；
///   * 子任务内新建的 span 挂接到父任务激活 span（`child_span.parent == ctx.span`）；
///   * 子任务内事件被标注子 span 与父 trace；
///   * 退出 `with_context` 后父任务的 trace 与激活 span 状态被原样还原。
fn prop_ls_trace_propagation(rng : @infra_pbt.Rng) -> Bool {
  reset_logger()
  let parent_trace = begin_trace()
  // 构造随机深度（≥1）的父任务激活 span 栈。
  let depth = rng.next_range(1, 4)
  let outer : Array[Span] = []
  for d in 0..<depth {
    outer.push(enter_span("outer\{d}"))
  }
  // 在父任务侧捕获上下文（当前 trace + 最内层激活 span）。
  let ctx = capture_context()
  let child = child_context(ctx)
  // 子上下文保留父 trace 标识。
  if child.trace != parent_trace {
    return false
  }
  if ctx.trace != parent_trace {
    return false
  }
  // 记录跨边界前的父任务状态，供还原校验。
  let trace_before = current_trace()
  let active_before = current_span()
  // 在传播的子上下文下运行一段子任务工作，返回其内部不变量是否成立。
  let inner_ok = with_context(child, fn() {
    let mut good = true
    // 子任务保留父 trace 标识。
    if current_trace() != parent_trace {
      good = false
    }
    // 子 span 挂接父任务激活 span。
    let cs = enter_span("child")
    if cs.parent != ctx.span {
      good = false
    }
    // 激活子 span 内事件标注子 span 与父 trace。
    log(Level::Info, {})
    let ev = captured_events()
    let last = ev[ev.length() - 1]
    match last.fields.get("trace") {
      Some(VInt(v)) => if v != parent_trace.value { good = false }
      _ => good = false
    }
    match last.fields.get("span") {
      Some(VInt(v)) => if v != cs.id.value { good = false }
      _ => good = false
    }
    exit_span(cs)
    good
  })
  if !inner_ok {
    return false
  }
  // 退出子任务后父任务状态被原样还原。
  if current_trace() != trace_before {
    return false
  }
  if current_span() != active_before {
    return false
  }
  // 逆序退出父任务激活 span，恢复运行时状态。
  for d = outer.length() - 1; d >= 0; d = d - 1 {
    exit_span(outer[d])
  }
  true
}

// ---------------------------------------------------------------------------
// 单元测试（具体见证）—— 锁定代表性场景
// ---------------------------------------------------------------------------

///|
/// Property 16 的具体见证：阈值 Warn 时仅 Warn / Error 被保留且保持原序，
/// Trace / Debug / Info 被丢弃。
test "level threshold filtering drops below-threshold events (witness)" {
  reset_logger()
  set_threshold(Level::Warn)
  log(Level::Trace, { "seq": VInt(0L) })
  log(Level::Warn, { "seq": VInt(1L) })
  log(Level::Info, { "seq": VInt(2L) })
  log(Level::Error, { "seq": VInt(3L) })
  log(Level::Debug, { "seq": VInt(4L) })
  let events = captured_events()
  // 仅保留 seq=1(Warn) 与 seq=3(Error)，且保持原序。
  @test.assert_eq(events.length(), 2)
  assert_true(events[0].level == Level::Warn)
  assert_true(events[1].level == Level::Error)
  match events[0].fields.get("seq") {
    Some(VInt(v)) => @test.assert_eq(v, 1L)
    _ => fail("首个保留事件应带 seq=1")
  }
  match events[1].fields.get("seq") {
    Some(VInt(v)) => @test.assert_eq(v, 3L)
    _ => fail("第二个保留事件应带 seq=3")
  }
}

///|
/// Property 17 的具体见证：嵌套 span 形成 span 树，激活 span 内事件被标注当前
/// span 与 trace 上下文。
test "nested spans form a tree and annotate events (witness)" {
  reset_logger()
  let trace = begin_trace()
  let root = enter_span("root")
  assert_true(root.parent is None)
  let child = enter_span("child")
  // 子 span 父为根 span。
  match child.parent {
    Some(pid) => @test.assert_eq(pid.value, root.id.value)
    None => fail("子 span 应挂接根 span")
  }
  // 激活（最内层 child）span 内事件标注该 span 与 trace。
  log(Level::Info, {})
  let events = captured_events()
  let last = events[events.length() - 1]
  match last.fields.get("span") {
    Some(VInt(v)) => @test.assert_eq(v, child.id.value)
    _ => fail("事件应标注当前 span")
  }
  match last.fields.get("trace") {
    Some(VInt(v)) => @test.assert_eq(v, trace.value)
    _ => fail("事件应标注当前 trace")
  }
  exit_span(child)
  exit_span(root)
}

///|
/// Property 17 的具体见证：跨 with_context 边界传播 trace，子 span 挂接父激活
/// span，退出后父状态还原。
test "with_context propagates trace and restores parent state (witness)" {
  reset_logger()
  let parent_trace = begin_trace()
  let outer = enter_span("outer")
  let ctx = capture_context()
  let trace_before = current_trace()
  let active_before = current_span()
  let inner_ok = with_context(child_context(ctx), fn() {
    let mut good = true
    if current_trace() != parent_trace {
      good = false
    }
    let cs = enter_span("inner")
    // 子任务 span 挂接父任务激活 span（outer）。
    match cs.parent {
      Some(pid) => if pid.value != outer.id.value { good = false }
      None => good = false
    }
    exit_span(cs)
    good
  })
  assert_true(inner_ok)
  // 退出后父状态还原。
  assert_true(current_trace() == trace_before)
  assert_true(current_span() == active_before)
  exit_span(outer)
}

// ---------------------------------------------------------------------------
// Property 16：日志级别阈值过滤（holds_for_all 模板，≥100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 16: 日志级别阈值过滤
///
/// 对任意随机阈值与随机级别事件序列，级别不低于阈值的事件被保留且保持原序，
/// 低于阈值的事件被丢弃。复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认
/// 迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 7.2, 7.3, 7.4, 7.6**
test "Feature: moonbit-infra-suite, Property 16: log level threshold filtering (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { prop_ls_level_filter(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

// ---------------------------------------------------------------------------
// Property 17：Span 树与 trace 上下文传播不变量（holds_for_all 模板，≥100 迭代）
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 17: Span 树与 trace 上下文传播不变量（span 树 + 事件标注）
///
/// 对任意随机深度的嵌套 span 序列，根 span 无父、嵌套 span 父为外层 span 形成
/// span 树，且激活 span 内事件被标注当前 span 与 trace 上下文标识。复用
/// @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 7.2, 7.3, 7.4, 7.6**
test "Feature: moonbit-infra-suite, Property 17: nested spans form a tree and annotate events (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { prop_ls_span_tree(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// Feature: moonbit-infra-suite, Property 17: Span 树与 trace 上下文传播不变量（跨任务边界传播）
///
/// 对任意随机深度的父任务激活 span 栈，跨 `with_context` 边界运行的子任务保留
/// 父任务 trace 标识、其新建 span 挂接父任务激活 span、事件被标注子 span 与父
/// trace，且退出后父任务 trace 与激活 span 状态被原样还原。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 7.2, 7.3, 7.4, 7.6**
test "Feature: moonbit-infra-suite, Property 17: with_context propagates parent trace and restores state (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { prop_ls_trace_propagation(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}
