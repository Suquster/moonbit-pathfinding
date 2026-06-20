// incremental_ext.mbt —— L1 错误恢复组合子（Requirement 6.3 / design.md
// §「Parser Combinator 增强设计 → AC3 withRecovery」）。
//
// 本文件以「冻结现有 API + 仅新增（bypass）」策略，在既有 `Grammar[T]` /
// `recover` 之上新增「策略化错误恢复」组合子 `with_recovery`：当被包裹的子
// 解析在某位置失败时，按 `RecoveryStrategy` 同步到标记位置，产出调用方给定的
// 占位值（placeholder）使整体解析得以继续，而非中断。
//
// 与既有 `recover(Grammar[T], Grammar[Unit], T)` 的区别：
//   * `recover` 仅在「硬失败（committed）」时触发，且以一个 `Grammar[Unit]`
//     同步文法扫描、越过同步点后续解；
//   * `with_recovery` 在「任意失败」时触发（软/硬失败均恢复），并以轻量的
//     字符级策略 `RecoveryStrategy` 同步，便于 `many` / 序列解析在元素级失败
//     后继续推进。
//
// 二者互不影响、签名均不改动，满足 only-add（bypass）约束。

///|
/// 错误恢复策略（recovery strategy）。
///
///   * `SkipUntil(c)` —— 从失败位置起跳过输入字符，直到**遇到**标记字符 `c`；
///   * `SyncTo(chars)` —— 从失败位置起跳过输入字符，直到遇到 `chars` 中**任一**
///     同步标记。
///
/// 同步停靠语义（关键约定，二者一致）：扫描在「遇到标记字符时」停下，且
/// **停在该标记字符之前**（不消费该标记），即恢复完成后游标正好指向标记
/// 字符（后续 `peek` 返回该标记）。如此可把标记字符（通常是分隔符 `,` / 闭合
/// 符 `}` `]` 等）留给外层解析器处理，便于 `sep_by` / `many` / `between` 在元素
/// 级失败后无缝接管同步标记并继续。
pub enum RecoveryStrategy {
  SkipUntil(Char)
  SyncTo(Array[Char])
} derive(Eq)

///|
/// 以可读形式展示恢复策略（便于诊断与测试失败信息阅读）。
///
/// 手写 `Show`（而非 `derive(Show)`）以规避 `derive(Show)` 的弃用告警，与
/// `build_tool` 包 `Action` / `ActionResult` 的处理一致；逐字段经
/// `logger.write_string` 写出，不做循环字符串拼接（无 `out = out + ...` 反模式）。
pub impl Show for RecoveryStrategy with fn output(
  self : RecoveryStrategy,
  logger : &Logger,
) -> Unit {
  match self {
    SkipUntil(c) => {
      logger.write_string("SkipUntil(")
      logger.write_string(c.to_string())
      logger.write_string(")")
    }
    SyncTo(chars) => {
      logger.write_string("SyncTo([")
      let mut first = true
      for ch in chars {
        if !first {
          logger.write_string(",")
        }
        logger.write_string(ch.to_string())
        first = false
      }
      logger.write_string("])")
    }
  }
}

///|
/// `with_recovery(g, strategy, placeholder)`：策略化局部错误恢复组合子。
///
/// 行为（严格对应 Requirement 6.3）：
///   * `g` 成功（`OOk`）→ **原样返回**成功结果，不触发恢复；
///   * `g` 失败（`OFail`，软失败或硬失败均触发）→ 从失败位置起，按
///     `strategy` 跳过输入字符同步到标记位置（停在标记前、不消费），随后以
///     `placeholder` 作为该位置的产出值返回 `OOk(placeholder, 同步后输入)`，
///     使整体视为「成功」以便外层组合子继续解析。
///
/// 起始扫描位置：取「失败位置」与「进入位置」中偏移更大者，从该处向前扫描，
/// 从而不重复跳过已被 `g` 成功消费的合法前缀（失败可能发生在序列解析的更深处）。
///
/// 终止性说明：扫描在有限的剩余字符上向前推进，必停于标记字符或输入末尾，
/// 故 `with_recovery` 自身必然终止。注意：由于同步「停在标记之前」（不消费
/// 标记），若调用方在 `many` 中直接以「会立即失败且当前字符即为标记」的方式
/// 重复调用本组合子，可能因游标不前进而循环——此为调用方组合方式的责任，
/// 标准用法（配合 `sep_by` 消费分隔符）不受影响。
pub fn[T] with_recovery(
  g : Grammar[T],
  strategy : RecoveryStrategy,
  placeholder : T,
) -> Grammar[T] {
  Grammar::new(fn(ctx, input) {
    match pc_run(g, ctx, input) {
      OOk(v, rest) => OOk(v, rest)
      OFail(fail_pos, _, _) => {
        // 从「失败位置」与「进入位置」中偏移更大者开始向前同步。
        let start = recovery_scan_start(input, fail_pos)
        let synced = match strategy {
          SkipUntil(marker) => scan_skip_until(start, marker)
          SyncTo(markers) => scan_sync_to(start, markers)
        }
        OOk(placeholder, synced)
      }
    }
  })
}

///|
/// 内部辅助：选取恢复扫描的起始 `Input`。
///
/// 失败位置可能比进入位置更深（序列解析中前缀已成功消费），取偏移更大者作为
/// 起点，避免重复扫描已消费的合法前缀；并复用进入输入的共享只读 `chars`。
fn recovery_scan_start(input : Input, fail_pos : Pos) -> Input {
  if fail_pos.offset > input.pos.offset {
    { chars: input.chars, pos: fail_pos }
  } else {
    input
  }
}

///|
/// 内部辅助：跳过字符直到遇到标记 `marker`，停在标记之前（不消费标记）。
///
/// 经 `Input::advance` 沿共享 `chars` 推进游标（不做字符串 `+` 拼接）；遇标记
/// 或抵达末尾即停。
fn scan_skip_until(input : Input, marker : Char) -> Input {
  let mut cur = input
  let mut stop = false
  while not_done(stop) {
    match cur.peek() {
      None => stop = true
      Some(c) => if c == marker { stop = true } else { cur = cur.advance() }
    }
  }
  cur
}

///|
/// 内部辅助：跳过字符直到遇到 `markers` 中任一同步标记，停在标记之前。
fn scan_sync_to(input : Input, markers : Array[Char]) -> Input {
  let mut cur = input
  let mut stop = false
  while not_done(stop) {
    match cur.peek() {
      None => stop = true
      Some(c) =>
        if char_in(markers, c) {
          stop = true
        } else {
          cur = cur.advance()
        }
    }
  }
  cur
}

///|
/// 内部辅助：判断字符 `c` 是否属于标记集合 `markers`。
fn char_in(markers : Array[Char], c : Char) -> Bool {
  for m in markers {
    if m == c {
      return true
    }
  }
  false
}

///|
/// 烟雾测试：子解析成功时原样返回，不触发恢复。
test "with_recovery 成功路径原样返回" {
  let g = with_recovery(lift(pchar('a')), SkipUntil(','), '?')
  let r = g.run_naive_string("abc")
  assert_eq(r.is_ok(), true)
  assert_eq(r.value(), Some('a'))
  // 成功消费一个字符，剩余游标在 offset 1。
  match r.rest() {
    Some(rest) => assert_eq(rest.pos.offset, 1)
    None => assert_eq(true, false)
  }
}

///|
/// 烟雾测试：SkipUntil 在失败后跳到标记前并产出占位值。
test "with_recovery SkipUntil 跳到标记前" {
  // 子解析期望 'x' 但输入以 'a' 开头，于 offset 0 失败。
  let g = with_recovery(lift(pchar('x')), SkipUntil(','), '?')
  let r = g.run_naive_string("ab,cd")
  assert_eq(r.is_ok(), true)
  assert_eq(r.value(), Some('?'))
  // 跳过 'a' 'b'，停在 ',' 之前（offset 2，不消费 ','）。
  match r.rest() {
    Some(rest) => {
      assert_eq(rest.pos.offset, 2)
      assert_eq(rest.peek(), Some(','))
    }
    None => assert_eq(true, false)
  }
}

///|
/// 烟雾测试：SkipUntil 未遇标记时扫描到输入末尾。
test "with_recovery SkipUntil 无标记扫描到末尾" {
  let g = with_recovery(lift(pchar('x')), SkipUntil(';'), '?')
  let r = g.run_naive_string("abc")
  assert_eq(r.is_ok(), true)
  match r.rest() {
    Some(rest) => {
      assert_eq(rest.is_eof(), true)
      assert_eq(rest.pos.offset, 3)
    }
    None => assert_eq(true, false)
  }
}

///|
/// 烟雾测试：SyncTo 跳到任一同步标记前。
test "with_recovery SyncTo 同步到任一标记" {
  let g = with_recovery(lift(pchar('x')), SyncTo([')', ']', '}']), '_')
  let r = g.run_naive_string("abc] rest")
  assert_eq(r.is_ok(), true)
  assert_eq(r.value(), Some('_'))
  // 跳过 'a' 'b' 'c'，停在 ']' 之前（offset 3）。
  match r.rest() {
    Some(rest) => {
      assert_eq(rest.pos.offset, 3)
      assert_eq(rest.peek(), Some(']'))
    }
    None => assert_eq(true, false)
  }
}

///|
/// 烟雾测试：RecoveryStrategy 派生 Eq / Show 正常。
test "RecoveryStrategy 派生 Eq/Show" {
  assert_eq(SkipUntil(','), SkipUntil(','))
  assert_eq(SyncTo([',', ';']), SyncTo([',', ';']))
  assert_eq("\{SkipUntil(',')}", "SkipUntil(,)")
}
