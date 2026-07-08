# 全仓覆盖率审计（2026-07-08，native, moon coverage analyze）

三后端 2502 测试全绿基线下的未覆盖行盘点。总计 2332 行，分布与定性如下。

方法：`moon coverage clean && moon test --enable-coverage --target native && moon coverage analyze`。

## 按包汇总（未覆盖行数降序）

| 包 | 未覆盖行 | 定性 |
|---|---:|---|
| src/serialization | 292 | 核心库 |
| src/mini_compiler | 270 | 核心库 |
| src/codegen_infra | 155 | 核心库 |
| src/infra_compress | 152 | 核心库 |
| benches/advanced_bench | 126 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/proofs | 106 | 核心库 |
| bench_rust/moon_side | 98 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/lsp_server | 87 | 核心库 |
| src/dst | 64 | 核心库 |
| src/logging | 63 | 核心库 |
| src/infra_bench | 61 | 核心库 |
| src/infra_codec | 59 | 核心库 |
| src/actor | 50 | 核心库 |
| src/infra_config | 50 | 核心库 |
| src/parser_combinator | 50 | 核心库 |
| src/directed | 49 | 核心库 |
| src/infra_time | 48 | 核心库 |
| src/infra_ds | 45 | 核心库 |
| src/build_tool | 40 | 核心库 |
| examples/eight_puzzle | 35 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/lsp_binding | 35 | 核心库 |
| src/infra_text | 29 | 核心库 |
| examples/network_routing | 28 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| examples/maze_solver | 27 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/infra_diff | 24 | 核心库 |
| src/playground | 24 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/graph | 23 | 核心库 |
| src/regex_engine | 20 | 核心库 |
| benches/infra_ds_bench | 18 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/advanced | 18 | 核心库 |
| src/infra_resilience | 17 | 核心库 |
| benches/stress_bench | 16 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/infra_cli | 16 | 核心库 |
| benches/lsp_bench | 14 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/infra_metrics | 14 | 核心库 |
| benches/actor_bench | 12 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/infra_text_bench | 10 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/mini_compiler_bench | 8 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/codegen_bench | 7 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/infra_hash | 7 | 核心库 |
| src/infra_pbt | 7 | 核心库 |
| src/mooncakes_audit | 6 | 核心库 |
| src/infra_fuzz | 5 | 核心库 |
| benches/build_tool_bench | 4 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/infra_alloc_bench | 4 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/serialization_bench | 4 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/backend_cli | 4 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/infra_alloc | 4 | 核心库 |
| src/infra_timer | 4 | 核心库 |
| src/unweighted | 4 | 核心库 |
| benches/infra_codec_bench | 3 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/infra_timer_bench | 3 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/release_aggregate | 3 | 核心库 |
| benches/infra_metrics_bench | 2 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/kruskal_bench | 2 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/bfs_bench | 1 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/dijkstra_bench | 1 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| benches/regex_bench | 1 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| cmd/main | 1 | 驱动/示例（CI bench/demo 通道执行，不计单测覆盖） |
| src/road_service | 1 | 核心库 |
| src/undirected | 1 | 核心库 |

## 定性结论

1. **驱动/示例代码**（benches/、examples/、bench_rust/、cmd/、playground、backend_cli）
   占未覆盖大头：这类入口由 CI 基准通道与部署演示执行，不进入单测覆盖统计，
   属预期豁免，不做补测。
2. **核心库剩余未覆盖行**主要为三类：
   - Show/打印辅助（如 mini_compiler/match_ext 的诊断输出）——仅诊断可读性，
     错误信息路径在失败分支才触达；
   - 防御性兜底分支（结构不可达的 `None => break` / 损坏输入预拒绝，代码内
     已有注释说明，如 regex_engine、zstd_block 摆表校验）；
   - 深层畸形输入错误路径（proto_grammar/toml/json 解析器的截断输入分支）。
3. **regex_engine 已作深度收口示范**：未覆盖行 100+ → 20，剩余全部为文档化
   防御兜底（见 evidence_index.psv 对应行）。其余核心包按同法可继续收口，
   优先级：serialization > infra_compress > mini_compiler > infra_config。
