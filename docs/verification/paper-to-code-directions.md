# Paper-to-Code 追溯 · 十大生产化方向（§C5）

> 目的：为每个方向建立「论文/规范原文构造 → 代码位置 → 验证测试」的可审计追溯链。
> 高级寻路三算法（CH / JPS / ALT）另见 `paper-to-code-advanced.md`。
> 全部条目三后端（native / wasm-gc / js）测试全绿、0 告警。

---

## 方向一 · Mini_Compiler

| 论文/规范构造 | 代码位置 | 验证测试 |
|---|---|---|
| Damas & Milner 1982 Algorithm W：合一 + occurs check + let-多态泛化/实例化 | `src/mini_compiler/infer.mbt` | 推断单测 + 求值/类型一致 PBT |
| Maranget 2007 *Warnings for pattern matching*：矩阵特化 𝒮 / 默认行 𝒟 / usefulness 𝒰、缺失模式见证构造 | `src/mini_compiler/exhaustive.mbt`（`missing_witness`/`check_exhaustive`/`redundant_arms`） | `exhaustive_wbtest.mbt`：bool/list/tuple 定向 + 见证健全性 PBT 100 迭代 |
| Rémy 1993 / Gaster & Jones 1996 行多态：行重排引理 `rewrite_row`、开放行经行变量吸收缺字段、行 occurs check | `src/mini_compiler/row_poly.mbt`（`unify_rty`/`unify_row`/`normalize_rty`） | `row_poly_test.mbt`：开放/封闭记录、字段序无关、字段选择子 + 合一后两侧规范化相等 PBT 100 迭代 |
| WebAssembly 规范：lambda 提升 + funcref 表 `call_indirect`、线性内存环境链 | `src/mini_compiler/wasm_backend.mbt` | 22 例语料 wat2wasm + Node V8 执行与解释器逐字符一致（`docs/verification/backend-products-t1.md`） |
| Aho/Ullman 窥孔优化：跳转穿透、跳到下一条消除、不可达消除 | `src/mini_compiler/peephole.mbt`、`optimize.mbt` | 优化前后求值等价 PBT |

## 方向二 · Regex_Engine

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| Thompson 1968 NFA 构造 + Pike VM（RE2 同源）线性时间扫描 | `src/regex_engine/`（编译器/VM） | 与朴素回溯参照差分 PBT；病态输入线性时间 guard |
| 捕获组语义（PCRE 子集） | 同上 | 捕获定向用例 + 差分 |

## 方向三 · Codegen_Infra

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| Cytron et al. 1991 SSA；Wegman & Zadeck 1991 SCCP；Alpern/Click GVN（含 PRE 上提） | `src/codegen_infra/`（SCCP/GVN/CopyProp/DCE/ConstFold） | 每 pass「优化前后求值等价」PBT；真实语料 11 内核削减 40.1% |
| pass 流水线 + IR 验证器（每 pass 前后 SSA 良构断言） | `src/codegen_infra/pipeline.mbt`（`run_to_fixpoint`）+ `ir_validator.mbt` | `prop_pipeline_wbtest.mbt`、`ir_validator_wbtest.mbt` |
| Pelegrí-Llopart & Graham 1988 BURS 代价最优指令选择 | `src/codegen_infra/burs.mbt` | 最大吞噬对照基线 + 最优性 PBT |

## 方向四 · Parser_Combinator

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| Hutton & Meijer 1998 monadic 组合子；functor/monad/alternative 定律 | `src/parser_combinator/combinators.mbt` 等 | 定律 PBT（algebra_prop_test） |
| Ford 2002 PEG/packrat：位置×解析器记忆化，回溯型最坏复杂度降线性 | `src/parser_combinator/packrat.mbt`（`memoize`） | packrat-朴素差分一致 PBT；`benches/parser_packrat_bench` 确定性计数 guard：朴素 ≥2^(d-1) 指数、packrat ≤d+1 线性（d=16 计时 4004×） |
| Warth et al. 2008 seed-growing 直接左递归 | `src/parser_combinator/left_recursion.mbt` | 左递归文法 PBT |
| megaparsec `ParseErrorBundle` 同构错误报告：最远失败合并 + 期望集 + 源码行摘录/caret | `error_model.mbt`、`error_report.mbt` | `error_report_test.mbt` 5 项锁定 |

## 方向五 · LSP

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| LSP 3.17 / JSON-RPC 2.0：成帧（Content-Length CRLF/LF）、批处理、取消、进度、错误码 | `src/lsp_binding/`（`progress.mbt` 等） | 成帧往返 PBT 100 迭代 |
| Boehm et al. 1995 rope（join-based 平衡）：单点编辑 O(log N) | `src/lsp_server/rope_sync.mbt` | 与朴素字符串编辑等价 PBT 三编码；16384 行 228×（bench 工件） |
| 位置编码 UTF-8/16/32 互转 | `src/lsp_server/` | 三编码往返 PBT |

## 方向六 · Build_Tool

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| Mokhov et al. 2018 *Build Systems à la Carte*：内容寻址缓存 + 最小重建集 | `src/build_tool/build_tool.mbt`（`Action::fingerprint`/`BuildLog`） | rebuild-minimality/sufficiency/noop 三属性 PBT |
| 关键路径（remaining rank）列表调度（Graham 1966/Hu 1961 谱系） | `src/build_tool/scheduler.mbt`（`schedule_critical_path`） | makespan 达关键路径下界 guard + PBT（bench 工件 t62） |
| 三类前置校验：循环/缺失输入/写竞争（传递闭包序判定），确定性排序报错 | `src/build_tool/robustness.mbt`（`validate_build`） | `robustness_test.mbt` 确定性 PBT 100 迭代 |

## 方向七 · Logging / Tracing

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| OpenTelemetry 规范：span 上下文传播、OTLP 导出形态 | `src/logging/` | OTLP 导出黄金对比（`docs/verification/otlp-export-t7.md`） |
| `tracing` 结构化字段/层级订阅 | 同上 | 订阅路由/过滤单测 + PBT |

## 方向八 · DST

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| FoundationDB/TigerBeetle 式确定性仿真：种子可复现调度 + 故障注入 | `src/dst/` | 同种子逐字节一致 PBT；故障注入后不变量保持 |

## 方向九 · Serialization

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| protobuf wire format（varint/zigzag/length-delimited） | `src/serialization/` | 编解码往返 PBT + 黄金字节对比 |

## 方向十 · Actor_Framework

| 构造 | 代码位置 | 验证测试 |
|---|---|---|
| Erlang/OTP 监督树：OneForOne/OneForAll/RestForOne + 重启强度窗口（O(窗口) 修剪） | `src/actor/supervision*.mbt` | 确定性测试 + 风暴基准 685k events/sec、17087 次重启全恢复 |
| 有界邮箱 + 丢弃/阻塞背压策略 | `src/actor/bounded_mailbox.mbt` | 容量 PBT（P25） |
| ask 超时/乱序响应/关联 id 完整性 | `src/actor/ask.mbt` | PBT P11 + e2e |

## E1 · Infra_DS（核心数据结构库）

| 论文/规范构造 | 代码位置 | 验证测试 |
|---|---|---|
| CLRS §18 B-tree（t=8 单趟下降，预分裂/借位/合并） | `src/infra_ds/btree.mbt` | `btree_test.mbt` 差分 PBT 200 迭代；基准 insert+get 30.2×、range 29.2× |
| Chambi et al. 2016 Roaring（高 16 位分桶 + array/bitmap 两态容器） | `src/infra_ds/roaring.mbt` | `roaring_test.mbt` 差分 PBT 200/100 迭代；稠密并 103× |
| Bagwell 2001 HAMT（32 叉分片 bitmap+紧凑数组，路径复制结构共享） | `src/infra_ds/hamt.mbt` | `hamt_test.mbt` 差分 PBT 200 迭代；持久化插入 47× |
| Pugh 1990 SkipList（p=1/2 几何晋升，种子化确定性层高） | `src/infra_ds/skiplist.mbt` | `skiplist_test.mbt` 差分 PBT 200 迭代 + 同种子确定性；insert+get 15.1× |

## E4 · Infra_Timer（并发调度基础设施）

| 论文/规范构造 | 代码位置 | 验证测试 |
|---|---|---|
| Varghese & Lauck 1987 层级定时器轮（5 级×64 槽 + 回绕 cascade，摊销 O(1)） | `src/infra_timer/timer_wheel.mbt` | `timer_wheel_test.mbt` 与朴素 O(n) 扫描差分 PBT 200 迭代（逐 tick 到期集合一致）；基准 n=16000 281× |
| Chase & Lev 2005 工作窃取双端队列（环形缓冲 owner-LIFO/thief-FIFO 摊销 O(1)）+ 确定性轮转调度器 | `src/infra_timer/work_stealing.mbt` | `work_stealing_test.mbt` 无丢失无重复 + 同输入 trace 逐位一致 PBT 120 迭代；混合负载基准 15.1× |
| Masson et al. VLDB 2019 DDSketch（对数桶分位数 sketch，相对误差 ≤ α 可证明界，O(1) 插入可合并） | `src/infra_metrics/ddsketch.mbt` | `ddsketch_test.mbt` 误差界证明式 PBT 60 迭代（多分布多 α 对照精确分位）+ 合并误差界 40 迭代；流式 p99 基准 56.1× |
| Protocol Buffers Encoding 规范（LEB128 varint / zigzag sint64 / 小端 fixed32-64 / length-prefixed LEN） | `src/infra_codec/codec.mbt` | `codec_test.mbt` 边界值定向 + 畸形输入安全 + round-trip PBT 200 迭代（逐值一致、流精确耗尽）；吞吐 2.1×、体积 2.24×/4.47× |
| Gene Tene HdrHistogram（指数段 + 2^p 线性子桶纯位运算索引，相对误差 ≤ 2^-p，固定内存） | `src/infra_metrics/hdr_histogram.mbt` | `hdr_histogram_test.mbt` 误差界证明式 PBT 60 迭代（p∈{4,7,10} 多值域对照精确分位）；流式 p99.9 基准 217.8× |
