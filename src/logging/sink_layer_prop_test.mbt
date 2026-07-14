// sink_layer_prop_test.mbt —— Sink 层派发语义的属性测试（任务 3.2）。
//
// 覆盖 design.md §「正确性属性 · Property 2: R2 Sink 派发语义」：
//
//   Property 2: CallbackSink 对通过级别的记录恰好调用一次；BufferedSink
//               阈值前不下发、阈值或 flush 后按到达顺序全部下发；级别低于
//               生效级别的记录不交付任何下游。
//   **Validates: Requirements 2.2, 2.3, 2.4, 2.6**
//
// 本文件以全称量化（property）形式校验三条子性质，全部复用共享 PBT 包
// @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（每条属性显式 `iters`
// ≥ 100，满足质量门禁 ≥100 迭代基线），并在 wasm-gc / js / native 三后端运行。
//
// 观测策略（遵循 design.md「Console 用 Callback 等价建模做 PBT」）：
//   * Console 直写 stdout 不便在测试中断言，故统一以 CallbackSink 收集到一个
//     可变 `Array` 来观测「实际下发了什么、以何顺序下发」；
//   * 回调副作用观测点一律为可变数组（如 `Array[Event]` / `Array[Int64]` /
//     `Array[Level]`），避免引入任何全局状态，保证三后端可重放、互不串扰。
//
// 实现约束（遵循 quality-enforcement / anti-patterns 约定）：
//   * 仅新增测试，不改任何既有签名与既有测试；
//   * 不在循环内使用字符串 `+`（本文件不构建文本，仅比较事件/级别/时间戳）；
//   * 全程中文注释，每条属性带 `**Validates: Requirements 2.x**`。

///|
/// 测试用级别全集（与 `Level` 枚举一一对应，按 rank 递增排列）。
///
/// 集中命名以避免在多个生成器中重复字面量（遵循「禁止 magic number」约束）。
let prop_levels : Array[Level] = [Trace, Debug, Info, Warn, Error]

///|
/// 从随机源等概率抽取一个级别。
fn prop_gen_level(rng : @infra_pbt.Rng) -> Level {
  prop_levels[rng.next_below(prop_levels.length())]
}

///|
/// 生成一个随机的级别序列：长度 `0..=max_len`，每个元素等概率取自 `prop_levels`。
///
/// 用于驱动「按到达顺序下发」与「按级别过滤」两条性质的事件序列。
fn prop_gen_levels(rng : @infra_pbt.Rng, max_len : Int) -> Array[Level] {
  let n = rng.next_range(0, max_len)
  let levels : Array[Level] = []
  let mut i = 0
  while i < n {
    levels.push(prop_gen_level(rng))
    i = i + 1
  }
  levels
}

///|
/// Feature: production-hardening, Property 2: CallbackSink 通过级别恰好一次、不通过则零次
///
/// 对任意「sink 生效级别 sl × 事件级别 el」组合，构造一个仅对计数数组追加的
/// CallbackSink（`level=sl`），以一条级别为 el 的事件 `emit` 一次：
///   * 当 `el.rank() >= sl.rank()`（级别通过，AC2）：回调恰好被调用一次，
///     且收到的事件与输入事件相等；
///   * 当 `el.rank() < sl.rank()`（级别不通过，AC6）：回调一次都不被调用。
///
/// **Validates: Requirements 2.2, 2.6**
test "Feature: production-hardening, Property 2: callback sink delivers exactly once iff level passes" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (prop_gen_level(rng), prop_gen_level(rng))
  })
  let ok = @infra_pbt.holds_for_all(
    g,
    fn(pair) {
      let (sl, el) = pair
      // 回调副作用观测点：收集所有被下发的事件。
      let hits : Array[Event] = []
      let sink = SinkHandle::callback(fn(e) { hits.push(e) }, level=sl)
      let ev = Event::new(0L, el, Map([]))
      sink.emit(ev)
      if el.rank() >= sl.rank() {
        // AC2：级别通过 → 恰好一次，且内容一致（Event derive Eq）。
        hits.length() == 1 && hits[0] == ev
      } else {
        // AC6：级别不通过 → 零次。
        hits.length() == 0
      }
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 2: BufferedSink 阈值前不下发、阈值/flush 后按序全发
///
/// 对任意「阈值 K（1..=8）× 事件序列（长度 0..=20）」：构造 threshold=K 的
/// BufferedSink，下游为收集到达时间戳的 CallbackSink（默认 `Trace`，放行全部）。
/// 给每条事件赋予递增且唯一的时间戳 `0,1,2,...`，逐条 `emit` 并在每步校验：
///   * 已下发条数 == `(已 emit 条数 / K) * K`（整数除法）——即每满 K 条触发一次
///     批量下发，未满 K 条的尾部仍暂存不下发（AC3）；
///   * 已下发序列恰为到达顺序的前缀 `0,1,...,n-1`（AC4 按序）。
/// 全部 `emit` 后再 `flush`，校验：
///   * 下游最终收到全部事件，且严格按到达顺序 `0,1,...,N-1`（AC4 flush 全发）。
///
/// **Validates: Requirements 2.3, 2.4**
test "Feature: production-hardening, Property 2: buffered sink holds below threshold then flushes in arrival order" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    let k = rng.next_range(1, 8)
    (k, prop_gen_levels(rng, 20))
  })
  let ok = @infra_pbt.holds_for_all(
    g,
    fn(pair) {
      let (k, levels) = pair
      // 下游观测点：按到达顺序收集时间戳。
      let received : Array[Int64] = []
      let down = SinkHandle::callback(fn(e) { received.push(e.ts) })
      let buf = SinkHandle::buffered(k, down)
      let mut i = 0
      while i < levels.length() {
        // ts=i 保证唯一且与到达顺序一致。
        let ev = Event::new(i.to_int64(), levels[i], Map([]))
        buf.emit(ev)
        let emitted = i + 1
        // AC3：未满 K 条不下发；每满 K 条批量下发。
        let expected_delivered = emitted / k * k
        if received.length() != expected_delivered {
          return false
        }
        // AC4：已下发序列恰为到达顺序前缀。
        let mut j = 0
        while j < received.length() {
          if received[j] != j.to_int64() {
            return false
          }
          j = j + 1
        }
        i = i + 1
      }
      // AC4：显式 flush 后下游收到全部剩余缓冲，仍按到达顺序。
      buf.flush()
      if received.length() != levels.length() {
        return false
      }
      let mut j = 0
      while j < received.length() {
        if received[j] != j.to_int64() {
          return false
        }
        j = j + 1
      }
      true
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 2: 低于生效级别的记录不交付任何下游
///
/// 对任意「sink 生效级别 sl × 事件序列」：构造 `level=sl` 的 CallbackSink，
/// 收集所有被下发事件的级别后，校验：
///   * 下游收到的级别序列恰为「输入序列中级别通过（rank>=sl.rank）的子序列」，
///     顺序保持不变（既不漏发通过项，也不误发不通过项）；
///   * 下游收到的每一条级别均满足 `rank() >= sl.rank()`——即级别低于生效级别的
///     记录不出现在任何下游（AC6）。
///
/// **Validates: Requirements 2.6**
test "Feature: production-hardening, Property 2: below-level records are never delivered downstream" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (prop_gen_level(rng), prop_gen_levels(rng, 20))
  })
  let ok = @infra_pbt.holds_for_all(
    g,
    fn(pair) {
      let (sl, levels) = pair
      // 下游观测点：按到达顺序收集被下发事件的级别。
      let delivered : Array[Level] = []
      let sink = SinkHandle::callback(
        fn(e) { delivered.push(e.level) },
        level=sl,
      )
      // 参照子序列：仅保留级别通过的项，顺序不变。
      let expected : Array[Level] = []
      let mut i = 0
      while i < levels.length() {
        let lv = levels[i]
        let ev = Event::new(i.to_int64(), lv, Map([]))
        sink.emit(ev)
        if lv.rank() >= sl.rank() {
          expected.push(lv)
        }
        i = i + 1
      }
      // 下发集合与「通过项子序列」逐项一致。
      if delivered.length() != expected.length() {
        return false
      }
      let mut j = 0
      while j < delivered.length() {
        // 既校验顺序一致，又校验每条均不低于生效级别（AC6）。
        if delivered[j] != expected[j] || delivered[j].rank() < sl.rank() {
          return false
        }
        j = j + 1
      }
      true
    },
    iters=200,
  )
  assert_true(ok)
}
