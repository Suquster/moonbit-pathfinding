# INFRA 基准实测：配置 / diff（native）

- 日期：2026-07-12
- 工具链：moon 0.1.20260703 (6fbf8c3 2026-07-03)
- 命令（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）：
  - `moon bench -p benches/infra_config_bench --target native`
  - `moon bench -p benches/infra_diff_bench --target native`
- 环境：Ubuntu x86_64 CI 型虚拟机，结果为 `moon bench` 报告的 mean ± σ。

## 配置（infra_config，多段服务配置文本）

| bench | mean | σ |
|---|---:|---:|
| toml_parse_16_sections | 28.88 µs | 498.96 ns |
| ini_parse_16_sections | 66.76 µs | 2.60 µs |
| toml_parse_64_sections | 119.26 µs | 5.02 µs |
| ini_parse_64_sections | 258.72 µs | 5.47 µs |
| ini_get_64x3_lookups | 35.84 µs | 322.76 ns |

解读：两种解析器都随段数线性扩展（16→64 段约 4×）；64 段完整配置的
解析在 0.1–0.3 ms 之间，进程启动时一次性解析可忽略不计。

## diff（infra_diff，256 / 1024 行演化文本）

| bench | mean(256) | mean(1024) | 倍数 |
|---|---:|---:|---:|
| patch_roundtrip | 9.51 µs | 36.58 µs | 3.8× |
| diff_lines_myers | 33.19 µs | 329.05 µs | 9.9× |
| diff_patience | 42.67 µs | 180.68 µs | 4.2× |
| diff3_merge | 65.58 µs | 633.16 µs | 9.7× |
| diff_histogram | 165.39 µs | 2.91 ms | 17.6× |

解读：本负载（稀疏行改动）下 Myers 最快、patience 随规模扩展性更好、
histogram 因 token 频次统计开销最大——三种算法取舍与主流 git diff
实现的经验一致；补丁应用+回滚（patch_roundtrip）远快于重新计算 diff，
适合作为增量同步的热路径。

## 复现

以上均可用文首命令在 native 后端复现；冒烟测试
（`moon test -p benches/<name>`）校验了 TOML/INI 取值语义、补丁
apply/revert 往返与 diff3 无冲突合并，确保基准测的是真实语义。
