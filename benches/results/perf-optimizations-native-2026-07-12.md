# 性能优化实测：histogram diff / did-you-mean / ISO 8601 格式化（native）

- 日期：2026-07-12
- 工具链：moon 0.1.20260703 (6fbf8c3 2026-07-03)
- 对照：同机同负载，优化前后各跑 `moon bench --target native`
  （前值出自 `infra-config-diff-native-2026-07-12.md` 与
  `infra-time-resilience-cli-pbt-native-2026-07-12.md`）。

## 1. `diff_histogram`：行 intern + 数组直方图 + 均衡锚

改动（`src/infra_diff/histogram.mbt`）：

- 入口一次性把行 intern 为整数 id，递归内层全部走 `Array[Int]`，
  消除每层递归对每行的重复字符串哈希；
- 直方图从 `Map[String, Int]` 换成按 id 的数组计数（触碰过的 id
  在本层末尾清零，保持每层 O(区间长度)）；
- 构建直方图时同步记录首次出现下标，删除命中后 O(n) 的旧侧回扫
  （原实现该回扫使单层退化为 O(n²)）；
- 频次并列时选最靠近新侧区间中点的锚，使递归两侧规模均衡，
  避免链式切分退化。

| bench | 优化前 | 优化后 | 加速 |
|---|---:|---:|---:|
| diff_histogram_256 | 165.39 µs | 43.30 µs | 3.8× |
| diff_histogram_1024 | 2.91 ms | 211.04 µs | 13.8× |

256→1024 的扩展系数从 17.6× 降到 4.9×（接近线性），histogram 现已与
patience/Myers 同一量级，符合 git/JGit 的实践定位。

## 2. `suggest_option`：带上界 Damerau–Levenshtein

改动（`src/infra_cli/cli_typed.mbt`）：

- 新增 `dl_distance_bounded(a, b, limit)`：Ukkonen 对角带（只算
  |i−j| ≤ limit 的单元）+ 三行滚动（O(m) 内存）+ 行最小值超限提前退出；
  长度差 > limit 直接短路；
- `suggest_option` 以当前最优距离为上界逐候选收紧；
- `dl_distance` 语义不变（以 max(n,m) 为上界调用同一实现，结果精确）。

| bench | 优化前 | 优化后 | 加速 |
|---|---:|---:|---:|
| suggest_option_512 | 2.19 ms | 520.45 µs | 4.2× |

附带修复一个边界缺陷：候选距离恰为 `max_distance + 1` 时原实现会因
初始并列分支被错误接受，现严格遵守 ≤ `max_distance` 契约。

## 3. `format_iso8601` / `format_iso_date`：单 builder 直写

改动（`src/infra_time/time.mbt`）：

- `write_padded` 定宽十进制逐位直写 StringBuilder，替换原
  「pad 建串 → 插值再建串 → 拼接」路径（每次格式化 ~15 次中间分配
  降为 1 次输出分配）。

| bench | 优化前 | 优化后 | 加速 |
|---|---:|---:|---:|
| format_iso8601_256 | 140.85 µs | 44.98 µs | 3.1× |

## 正确性守卫

- `moon test`（含 infra_diff/infra_cli/infra_time 全部单测与
  patch_apply 往返、diff3、建议字典序决胜等语义测试）全绿；
- 基准包冒烟测试（补丁 apply/revert 往返、无冲突 diff3、
  ISO 8601 往返、did-you-mean 命中）全绿；
- `bash scripts/acceptance.sh` 六关门禁（含 20 demo 输出快照）通过。
