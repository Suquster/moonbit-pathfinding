// throughput.mbt —— 高吞吐批量调度驱动（旁路新增，冻结 `step` / `run_until_idle`）。
//
// 动机：`step()` 每处理一条消息都要做一次 O(A) 的全量就绪扫描与停止结算，
// 万级 actor × 十万级消息时扫描量达 10^9 次，吞吐坍缩。本驱动改为
// **轮转批量**（round-based batch）策略：每一轮按登记序遍历一次全部 actor，
// 对每个就绪 actor 连续排空其邮箱，轮末统一结算显式停止；反复至不动点。
// 扫描代价从 O(A × 消息数) 摊还到 O(A × 轮数 + 消息数)。
//
// 语义契约（与逐步驱动的差异明示）：
//   * 保持不变：单 actor 串行处理、per-actor FIFO、恰好一次处理、监督/重启、
//     行为切换 / stash / watch 全部效果（内部复用同一 `process_one` 流水线）；
//     终态（状态、trace 长度、停止结算）与逐步驱动一致。
//   * 有意不同：跨 actor 的全局处理交错顺序为「登记序轮转批量」而非
//     「每步重选最小就绪下标」；显式停止在轮末统一结算（返回前必然完成）。

///|
/// 轮转批量调度至空闲：反复整轮遍历（就绪者连续排空）+ 轮末结算停止，
/// 直至一轮内既无消息处理也无停止结算（不动点）。
pub fn[S, M] ActorSystem::run_until_idle_throughput(
  self : ActorSystem[S, M],
) -> Unit {
  while true {
    let mut progressed = false
    for i in 0..<self.cells.length() {
      let cell = self.cells[i]
      while cell.status is Running && !cell.mailbox.is_closed() {
        self.sync_bounded(cell)
        if self.cell_pending(cell) == 0 {
          break
        }
        self.process_one(cell)
        progressed = true
      }
    }
    let settled = self.settle_stops()
    if !progressed && !settled {
      break
    }
  }
}
