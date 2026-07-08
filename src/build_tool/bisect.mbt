// bisect.mbt —— 基准回归自动二分定位引擎（H-3，L7 自治工厂层）。
//
// paper-to-code：`git bisect` 的语义内核。给定线性 commit 序列
// （下标 0 为已知 Good 基线之后的首个候选，末位为已知 Bad 的回归现场）
// 与判定 oracle（构建 + 基准 guard），在「单调回归假设」（一旦变坏不再
// 变好）下二分定位**首个 Bad commit**：
//   * oracle 返回 Good / Bad / Skip（构建失败等不可判定，等价
//     `git bisect skip`：在邻域内寻找最近可判定点）；
//   * 全部探测结果记录在案（probe 日志），供 CI 工件回放；
//   * 探测次数上界 O(log n + skip 数)。
// 引擎为纯函数（oracle 以闭包注入），故可离线以任意假想历史做 PBT。

///|
/// 单次探测判定：好 / 坏 / 不可判定（跳过）。
pub(all) enum BisectVerdict {
  BisectGood
  BisectBad
  BisectSkip
} derive(Eq)

///|
/// 二分结果：定位到的首个 Bad 下标与探测日志 (下标, 判定)。
pub struct BisectReport {
  first_bad : Int?
  probes : Array[(Int, BisectVerdict)]
}

///|
/// 自动二分定位首个 Bad commit。
///
/// 前置：`n > 0`；下标 `n-1` 处于回归状态（调用方由 guard 触发保证），
/// 下标 `-1`（区间外基线）为 Good。oracle 对同一下标必须幂等。
/// Skip 处理：中点不可判定时向两侧最近可判定点探测；整个区间皆 Skip
/// 时保守收缩到右半（宁可多测不漏报）。返回 None 仅当所有探测均 Skip、
/// 无法给出任何 Bad 见证。
pub fn auto_bisect(n : Int, oracle : (Int) -> BisectVerdict) -> BisectReport {
  let probes : Array[(Int, BisectVerdict)] = []
  let memo : Map[Int, BisectVerdict] = Map([])
  fn probe(i : Int) -> BisectVerdict {
    match memo.get(i) {
      Some(v) => v
      None => {
        let v = oracle(i)
        memo.set(i, v)
        probes.push((i, v))
        v
      }
    }
  }

  let mut lo = 0
  let mut hi = n - 1
  let mut first_bad : Int? = None
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    // Skip 邻域扩散：从 mid 向两侧找最近可判定点。
    let mut pick = -1
    let mut verdict = BisectSkip
    let mut offset = 0
    while mid - offset >= lo || mid + offset <= hi {
      if mid + offset <= hi {
        let v = probe(mid + offset)
        if !(v == BisectSkip) {
          pick = mid + offset
          verdict = v
          break
        }
      }
      if offset > 0 && mid - offset >= lo {
        let v = probe(mid - offset)
        if !(v == BisectSkip) {
          pick = mid - offset
          verdict = v
          break
        }
      }
      offset = offset + 1
    }
    if pick < 0 {
      // 区间内全部 Skip：无法进一步定位。
      break
    }
    if verdict == BisectBad {
      first_bad = Some(pick)
      hi = pick - 1
    } else {
      lo = pick + 1
    }
  }
  { first_bad, probes }
}
