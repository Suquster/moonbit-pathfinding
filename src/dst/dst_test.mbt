// dst_test.mbt —— DST_Framework 骨架（task 13.1）的最小单元测试。
//
// 覆盖范围（仅骨架基线，完整调度/故障/重放属性测试属 task 13.3）：
//   * `Rng` 同种子确定性：相同种子产生逐位一致的随机序列（确定性可重放的
//     基石；该性质在三后端上必须一致）；
//   * 不同种子产生不同序列（随机源具备区分度）；
//   * 接口桩签名可用且数据流形态正确（step / inject_fault / run / replay）。

///|
/// Rng 同种子确定性：两个以相同种子构造的随机源，连续推进产生逐位一致序列。
test "rng is deterministic for the same seed" {
  let a = rng_new(0x1234_5678_9ABC_DEF0)
  let b = rng_new(0x1234_5678_9ABC_DEF0)
  let mut i = 0
  while i < 64 {
    @test.assert_eq(a.next(), b.next())
    i += 1
  }
}

///|
/// 不同种子产生不同的首个随机字（随机源具备区分度，避免退化为常量序列）。
test "rng diverges for different seeds" {
  let a = rng_new(1)
  let b = rng_new(2)
  @test.assert_not_eq(a.next(), b.next())
}

///|
/// 零种子被安全地回退为非零状态，仍能产生非零随机序列（规避 xorshift 零不动点）。
test "rng_new handles zero seed without collapsing to zero" {
  let r = rng_new(0)
  @test.assert_not_eq(r.next(), 0)
}

///|
/// next_below 始终落在 [0, n) 区间内；n <= 0 时安全返回 0。
test "rng next_below stays within bounds" {
  let r = rng_new(42)
  let mut i = 0
  while i < 100 {
    let v = r.next_below(10)
    assert_true(v >= 0 && v < 10)
    i += 1
  }
  @test.assert_eq(rng_new(7).next_below(0), 0)
}

///|
/// 接口桩可用：step / inject_fault 保持 Sim 数据流形态，run / replay 回填种子。
test "skeleton stubs expose the designed interface shape" {
  let tasks = [Task::new(0, "build"), Task::new(1, "test")]
  let sim = Sim::new(99, tasks)
  // step / inject_fault 桩当前为占位（task 13.2 落地完整逻辑），此处仅验证可调用。
  let _ = sim.step()
  let _ = sim.inject_fault(FaultPolicy::new(1, 0, FaultKind::Crash))
  // run / replay 桩回填种子，锁定 SimResult 数据流形态。
  let scenario = Scenario::new(tasks, [], 16)
  let result = run(123, scenario)
  @test.assert_eq(result.seed, 123)
  let replayed = replay(123, result.trace)
  @test.assert_eq(replayed.seed, 123)
}
