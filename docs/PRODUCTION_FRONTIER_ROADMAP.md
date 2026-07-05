# 生产前沿纲领（Production-Frontier Roadmap）

> **总领性 / 纲领性文件 · 活文档（living document）· 中文撰写**
> 版本：v2（强化版） · 维护：随每个任务完成即更新勾选 + PR 链接 + benchmark 证据。
>
> **目标（用户主线，不可动摇）**：把十大方向**逐个**从「教学/竞赛级」真正捅到
> **当下各领域工业界最前沿、最成熟的真实落地水平**——对标 Rust `regex`·RE2、
> protobuf·prost、LLVM·Cranelift、Erlang/OTP·Akka、OpenTelemetry·`tracing`、
> FoundationDB·TigerBeetle 这类真实生产系统，而非研究/教学示意。
>
> **重要立场（用户明确、反复强调）**：本纲领**不被 spec / 附录里「玩具」「教学级」
> 「非目标」「实现边界」等措辞封顶**。凡是真实前沿成熟实现具备、而本库曾声明「不做」
> 的能力（真·并发运行时、真·wasm/js 产物、真·跨语言互通、真·OTLP 导出器…），
> 一律视为**要深化、拔高、加难度去攻克的目标**，而非可回避的边界。**只能加强难度，
> 不能降格。**

---

## 第 0 章 · 总纲与判据

### 0.1 「触及生产前沿」的五条硬判据（缺一不可）

一个方向被判定为「触及生产前沿」，当且仅当**同时**满足下列五条，且每条都有
仓库内可复现证据（代码 / 测试 / benchmark / 文档）：

| # | 判据 | 含义 | 证据形式 |
|---|------|------|---------|
| C1 | **算法/数据结构对标** | 核心结构与算法与该领域公认顶尖实现同级，非骨架、非占位 | 代码 + paper-to-code 文档 |
| C2 | **性能对标** | 相对自身朴素基线有**可量化、显著或数量级**提升，且对标实现的关键加速手段已落地 | `benches/results/` 工件 + 回归 guard |
| C3 | **正确性对标** | 以差分一致性 / conformance 语料 / 属性测试（≥100 迭代）证明与权威实现**逐位/逐字段等价** | PBT + 黄金语料 |
| C4 | **鲁棒性对标** | 覆盖负例、边界、对抗性输入；无 panic、无指数爆炸、无 O(n²) 热路径 | 负例回归测试 + 复杂度 guard |
| C5 | **可解释性对标** | paper-to-code 追溯（论文→代码→测试），并文档化与对标实现的取舍差异 | `docs/` 追溯文档 |

### 0.2 单任务「完成定义」（Definition of Done, DoD）

任何标记 `[x]` 的任务必须满足**全部**：

1. **功能落地**：真实实现，非占位 / 非恒真谓词 / 非 mock（除非该 mock 本身即对标目标的合法建模）。
2. **三后端一致**：`moon test --target wasm-gc|native|js` 全绿，无后端分歧。
3. **零告警**：`moon check` 输出 0 告警、0 错误（守住 PR #12 成果）。
4. **API 只增不减**：`moon info` 后 `git diff '*.mbti'` 仅含**新增**条目，不破坏既有公开 API。
5. **属性测试**：核心正确性属性以 `@infra_pbt` 实现，**≥100 迭代**（差分/往返/不变量类 ≥200）。
6. **基准证据**（性能类任务）：`benches/results/` 落可复现工件（机器/后端/规模/基线对比），并接入回归 guard。
7. **可解释性**：paper-to-code 追溯与对标差异写入对应 `docs/` 或 `README.mbt.md`。
8. **格式化**：`moon fmt` 已执行。

### 0.3 统一验证协议（每个 PR 必跑）

```bash
moon fmt                                  # 格式化
moon info                                 # 刷新 .mbti
git diff --stat -- '*.mbti'               # 确认接口只增不减
moon check                                # 0 告警 0 错误
moon test --target wasm-gc                # 后端一致性①
moon test --target native                 # 后端一致性②
moon test --target js                     # 后端一致性③
# 性能类任务追加：
pwsh -File scripts/benchmark_native.ps1   # 生成基线
pwsh -File scripts/benchmark_native_guard.ps1   # 回归门禁
```

### 0.4 全局 KPI（纲领级量化目标）

- **告警**：长期保持 0（任何 PR 不得引入新告警）。
- **测试**：三后端测试数只增不减（当前基线 1920），新增能力必带新增测试。
- **性能**：每个性能类任务相对朴素基线给出**明确加速比**（写入 benchmark README）。
- **正确性**：差分/conformance 类任务覆盖**≥90% 关键分支**。
- **可解释性**：每个方向有 1 份 paper-to-code 追溯文档，链接论文章节→代码块→测试。

---

## 第 1 章 · 十大方向作战卡

> 每张卡格式：**当前定位 → 对标标杆（真实工具 + 论文）→ KPI 目标 → 任务分解（带验收）→ 依赖与风险**。
> 任务状态：`[ ]` 待办 · `[~]` 进行中 · `[x]` 完成（附 PR / 证据）。

---

### 方向二 · Regex_Engine（正则引擎）— 对标 Rust `regex` / RE2

**当前定位**：Thompson NFA + Pike VM + 惰性 DFA + DFA 最小化 + hybrid 切换 + Unicode GC。
算法骨架对标 RE2 思路，但缺少生产引擎最关键的「**不进 VM 就先跳过**」预过滤层。

**对标标杆 / 论文**：Rust `regex` crate（Andrew Gallant）、RE2（Russ Cox）；
Thompson 1968、Cox "Regular Expression Matching Can Be Simple And Fast" 系列、
Aho-Corasick（多模匹配）、Teddy（SIMD 字面量匹配）。

**KPI 目标**：稀疏命中长文本（≥64KB，命中率 <1%）场景，预过滤路径相对纯 Pike VM
**≥5× 提速**；差分正确性 100%（开/关预过滤逐位相等，≥200 迭代）。

**任务分解**：
- [x] **T2.1 字面量预过滤（first-set prefilter）** ✅：从 AST 提取「匹配必经首字符集」
      （保守**超集**，含 case-fold），在 Pike VM 播种前快速跳过不可能起点。
      *证据*：差分 PBT `prop_prefilter_test.mbt`（≥200 迭代，逐字段相等）；native bench
      稀疏长文本 **5.58 ms → 276.5 µs（≈20.2×）**，见 `benches/results/regex-prefilter-t2.1-native.md`；
      确定性 guard 证明预过滤裁掉 >95% 播种位置。三后端 1925 测试全绿、0 告警、.mbti 只增。
- [x] **T2.2 必经字面量串 + Aho-Corasick 多模扫描** ✅：`aho_corasick.mbt` 实现 trie+失配链
      自动机；`prefilter.mbt` 对 `Concat`/`Alt` 提取必经字面量前缀集，多模一次扫描（`PfLiterals`）。
      *证据*：`prop_ac_prefilter_test.mbt`（AC 本体与朴素多模扫描逐位对拍、编译策略见证、
      差分 PBT ≥200 迭代 + 12 代表性见证）；三后端 1937 测试全绿、0 告警、.mbti 只增。
- [x] **T2.3 引擎自动选择** ✅：`engine_select.mbt` 按模式特征（纯字面量/捕获组/零宽断言/
      匹配策略）在字面量直扫（`EngLiteralScan`，AC 单模）/ 容量受限惰性 DFA（`EngLazyDfa`，
      状态缓存上限 512）/ Pike VM 间编译期择优，对调用方透明；决策经 `Pattern.engine` 字段可观测，
      `without_auto_engine` 供差分对照。*证据*：`prop_engine_select_test.mbt`（决策见证 +
      差分 PBT ≥200 迭代 + 代表性见证，与强制 Pike VM 逐位相等）。
- [x] **T2.4 对抗性鲁棒性回归** ✅：`prop_adversarial_test.mbt` 对 7 个经典 ReDoS 形态
      （`(a*)*b`、`(a+)+b`、`(a|a)*b`、深嵌套、量词展开、巨型字符类）断言硬上界
      `steps ≤ ninst×(n+1)`，并以倍增输入验证步数增速线性 + 语义健全性，证明无指数爆炸。

**依赖与风险**：无外部依赖；SIMD（Teddy）在 MoonBit 三后端上以标量等价实现（语义对标、性能尽力）。

---

### 方向九 · Serialization（序列化）— 对标 protobuf / `prost`

**当前定位**：proto3 wire format（varint/zigzag/定长/LEN）真实正确、Any、流式编解码、
代码生成、JSON 映射、解码错误偏移 + 无部分产物 PBT。

**对标标杆 / 论文**：Google protobuf（C++/Java/Go）、`prost`(Rust)；
Protocol Buffers Encoding 官方规范、protobuf conformance test suite。

**KPI 目标**：wire format 关键分支覆盖 ≥90%；与权威字节向量逐字节一致；
unknown field 往返保真 100%。

**任务分解**：
- [x] **T9.1 protobuf conformance 黄金语料** ✅：`conformance/`（gen_corpus.py 离线用
      protobuf 6.33.6 生成 corpus.golden）+ `conformance_test.mbt` 固化全 wire 分支黄金向量
      （varint 边界/zigzag/fixed/嵌套/packed/map），编解码逐字节一致，三后端全绿。
- [x] **T9.2 unknown field 保留** ✅：`typed.mbt` 解码保留未知字段（号/wire/原始取值）并在
      再编码原样回写。*证据*：`prop_unknown_test.mbt`（PBT）+ `unknown_reencode_test.mbt`
      （外来字节全 wire 类型 + 嵌套未知字段，解码-再编码**逐字节**保真）。
- [x] **T9.3 跨实现互通验证** ✅：黄金向量由真实 Google protobuf 运行时离线产出并固化
      （`conformance/gen_corpus.py` 可复现），`conformance_test.mbt` 证明本库独立实现与之
      逐字节互通（编码产出一致、解码消费一致）。
- [x] **T9.4 packed repeated + map 字段** ✅：proto3 packed 编解码（兼容非 packed wire
      形态）与 map 语法糖完整支持。*证据*：`prop_packed_test.mbt`（packed/非 packed 等价 PBT）、
      conformance 黄金向量含 packed 与 map 分支逐字节对齐。

**依赖与风险**：黄金向量需离线生成后固化进仓库（不在 CI 联网）。

---

### 方向三 · Codegen_Infra（代码生成基础设施）— 对标 LLVM / Cranelift

**当前定位**：SSA、支配树/支配边界、φ 插入、BURS 指令选择、图着色寄存器分配、
线性扫描、合并、GVN、SCCP、liveness。教科书核心齐全。

**对标标杆 / 论文**：LLVM、Cranelift；Cytron et al. 1991（SSA/支配边界）、
Briggs/Chaitin（图着色）、Poletto/Sarkar 1999（线性扫描）、Aho-Ganapathi-Tjiang（BURS）、
Click/Cooper（SCCP/GVN）。

**KPI 目标**：每个优化 pass 带「优化前后求值等价」PBT；pass 流水线含前后 IR 验证器断言。

**任务分解**：
- [x] **T3.1 Pass 流水线管理器 + IR 验证器** ✅：`run_to_fixpoint` + ir_validator（src/codegen_infra/pipeline.mbt），合成程序族削减 86.8%。
- [x] **T3.2 优化 pass 扩充** ✅：SCCP/GVN（含 PRE 上提）/CopyProp/DCE/ConstFold 均带等价 PBT；真实语料 11 内核削减 40.1%。
- [x] **T3.3 基于代价的指令选择** ✅：BURS 代价最优 tiling + 最大吞噬对照基线 + 最优性 PBT。

**依赖与风险**：无外部依赖；纯 IR 层，可三后端一致验证。

---

### 方向一 · Mini_Compiler（迷你编译器）— 对标教学/研究级 ML 编译器 + 真实产物

**当前定位**：MiniML 前端 + Algorithm W 类型推断 + 求值 + 栈式字节码 VM + peephole + TCO。
spec 曾声明为玩具/教学语言（不生成原生产物）——**本纲领突破该非目标**。

**对标标杆 / 论文**：OCaml/Haskell 教学实现、《Write You a Haskell》、WebAssembly 规范、
Damas-Milner（Algorithm W）、Hindley-Milner。

**KPI 目标**：emit 的 wasm/js 产物可被**真实运行时**（wasmtime / Node）执行，
端到端结果与树遍历解释器逐例一致。

**任务分解**（**突破** spec「玩具/不生成原生产物」非目标）：
- [x] **T1.1 真·WebAssembly 产物**：`wasm_backend.mbt` 把良类型 `TExpr` lower 到**合法完整
      wat 模块**（lambda 提升 + funcref 表 `call_indirect`、线性内存堆环境链/闭包/元组、
      `isrec` 递归自指），wat2wasm 汇编后由 Node V8 wasm 引擎真实执行，22 例语料与
      解释器逐字符一致（证据 docs/verification/backend-products-t1.md）。
- [x] **T1.2 真·JS 产物**：`js_backend.mbt` emit Node 可直接执行的 JS（32 位环绕
      `|0`/`Math.imul`、除零=0），端到端 22/22 与解释器一致；并顺带修复解释器
      `INT_MIN / -1` 陷阱 bug（三处统一环绕，回归锁定）。
- [x] **T1.3 类型推断深化** ✅：let-多态泛化/实例化（既有 infer.mbt）+ match 穷尽性/冗余 arm 检查（Maranget 2007 usefulness 算法含缺失模式见证，exhaustive.mbt）+ 行多态记录合一（Rémy/Gaster–Jones 行重排，row_poly.mbt，开放行吸收缺字段，见证健全性 PBT 100 迭代）。
- [x] **T1.4 字节码优化 + 诊断** ✅：常量折叠/DCE（optimize.mbt）+ 跳转穿透/跳到下一条消除/不可达消除（peephole.mbt，等价 PBT 既有）；类型错误报告 render_diagnostic：源码行摘录 + caret + 按消息形态的修复建议（Int/Bool 混用、非函数调用、元组元数、occurs、未绑定变量，diagnostics_ext.mbt）。

**依赖与风险**：wasm 产物的外部执行验证需 wasmtime/Node 可用（CI 可固化为黄金字节对比，外部执行作可选证据）。

---

### 方向四 · Parser_Combinator（解析器组合子）— 对标 `nom` / `megaparsec`

**当前定位**：functor/monad/alternative 定律、packrat 记忆化、直接左递归（seed-growing）、
增量流式解析、错误恢复、有界 packrat 缓存。

**对标标杆 / 论文**：`nom`(Rust)、`megaparsec`(Haskell)、Parsec；
Hutton & Meijer 1998、Ford 2002（PEG/packrat）、Warth et al. 2008（左递归）、Leijen & Meijer（Parsec）。

**KPI 目标**：packrat vs 朴素线性扩展趋势固化为 benchmark；错误消息含最远失败 + 期望集 + 源位置。

**任务分解**：
- [x] **T4.1 零拷贝/切片输入**：以位置索引而非复制子串推进，降低分配。
- [x] **T4.2 错误消息质量**：最远失败合并 + 期望集 + 源位置（对标 megaparsec `ParseErrorBundle`）。
- [x] **T4.3 性能基准** ✅：回溯密集歧义括号文法上 packrat 线性 vs 朴素指数（d=16 时 4004×），确定性原子求值计数 guard 锁定趋势（benches/parser_packrat_bench，工件 benches/results/parser-packrat-trend-t43-native-2026-07-05.md）。

**依赖与风险**：无外部依赖。

---

### 方向五 · LSP（语言服务器协议）— 对标 `tower-lsp` / `vscode-languageserver`

**当前定位**：JSON-RPC 2.0、Content-Length 成帧（CRLF/LF）、增量文档同步、位置编码（UTF-8/16/32）。

**对标标杆 / 规范**：`tower-lsp`(Rust)、`vscode-languageserver-node`；
LSP 3.17 规范、JSON-RPC 2.0 规范。

**KPI 目标**：长文档增量编辑达对数级更新；协议消息（批处理/取消/进度/错误码）全覆盖 + 成帧往返 PBT。

**任务分解**：
- [x] **T5.1 增量同步性能**：以 rope / piece-table 把长文档单次增量变更从次平方级降到对数级。
- [x] **T5.2 协议完整性**：批处理、取消（`$/cancelRequest`）、进度、标准错误码全覆盖 + 成帧往返 PBT。
- [x] **T5.3 能力语义**：定义跳转/补全/诊断的真实语义实现与一致性测试。

**依赖与风险**：无外部依赖；真实编辑器联调作可选证据。

---

### 方向六 · Build_Tool（构建工具）— 对标 Bazel / Buck2 / Ninja

**当前定位**：依赖图拓扑调度、并行波次、指纹增量构建、执行框架、构建日志、provenance。

**对标标杆 / 论文**：Bazel、Buck2、Ninja；Mokhov et al. "Build Systems à la Carte"（2018）。

**KPI 目标**：内容寻址缓存命中即跳过，证明最小重建集正确；关键路径调度缩短总时长。

**任务分解**：
- [x] **T6.1 内容寻址缓存** ✅：`Action::fingerprint`（cache_key 单射编码）+ `BuildLog::is_up_to_date` 命中即跳过；最小重建集正确性由 rebuild-minimality/sufficiency/noop 三属性锁定（prop_rebuild_*.mbt）。
- [x] **T6.2 关键路径调度** ✅：`schedule_critical_path`（remaining rank 降序堆优先列表调度）；链+扇出混合图 makespan 达关键路径下界，guard+PBT 锁定（benches/results/build-cp-schedule-t62-native-2026-07-05.md）。
- [x] **T6.3 鲁棒性回归** ✅：`validate_build` 三类前置校验——detect_cycle（既有）+ missing_inputs + write_conflicts（传递闭包序判定），确定性排序报错（robustness.mbt，确定性 PBT 100 迭代）。

**依赖与风险**：无外部依赖。

---

### 方向七 · Logging（结构化日志 / 分布式追踪）— 对标 `tracing` / OpenTelemetry

**当前定位**：事件/span 树/上下文、采样/限流/过滤/脱敏/指标、W3C traceparent、JSON + logfmt。
spec 曾声明不接真实 I/O / async / 墙钟——**本纲领突破「不做真实导出」非目标**。

**对标标杆 / 规范**：`tracing`(Rust)、OpenTelemetry SDK；
OTLP（OpenTelemetry Protocol）、W3C Trace Context、OTel 语义约定。

**KPI 目标**：产出可被真实 OTel collector 接收的 OTLP 字节；OTel 数据模型逐字段对齐。

**任务分解**（**突破** spec「不做真实导出/不接 async」非目标）：
- [x] **T7.1 真·OTLP 导出器**：`otlp_export.mbt` 按 OTLP（protobuf + JSON）线缆格式序列化
      span（`opentelemetry.proto.trace.v1.TracesData`，字段号逐一对齐官方 trace.proto），
      **复用方向九 protobuf 编码**；导出字节经官方 opentelemetry-proto 解码逐字段
      相等，可直接 POST 到真实 collector `/v1/traces`
      （证据 docs/verification/otlp-export-t7.md）。
- [x] **T7.2 OTel 语义逐字段对齐**：span 属性/事件/**链接（`SpanData::add_link`，OTLP
      `Span.links` 字段 13）**/状态（含 `status.message`）/资源（service.name）与 OTel
      数据模型对齐，导出字节经官方 opentelemetry-proto 解码逐字段相等
      （docs/verification/otlp-export-t7.md）。
- [x] **T7.3 采样器对标**：`samplers.mbt` 对标 OTel SDK 四种内置采样器
      （AlwaysOn/AlwaysOff/TraceIdRatioBased/ParentBased），确定性纯函数 +
      分布 PBT（10k trace 命中率与 rate 偏差 <2%）+ 保留集单调性；限流采样已有
      `RateLimiter`（sampling.mbt）。
- [x] **T7.4 高基数性能**：`prop_high_cardinality_test.mbt` 对 format_json /
      format_logfmt / OTLP 导出在倍增 n 序列上断言边际字节成本恒定（仿射、
      容差 ≤1 字节/项），杜绝二次膨胀；10k 字段高基数事件无损往返冒烟。

**依赖与风险**：OTLP 导出依赖方向九 protobuf 能力（先做 T9 再做 T7.1 更顺）。

---

### 方向八 · DST（确定性仿真测试）— 对标 FoundationDB / TigerBeetle / Antithesis

**当前定位**：可执行任务体、模拟网络（延迟/丢包/乱序/分区）、虚拟时钟、不变量/eventually、
确定性重放、DPOR 偏序规约、线性一致性检查、shrink。

**对标标杆 / 论文**：FoundationDB DST、TigerBeetle VOPR、Antithesis；
Flanagan & Godefroid 2005（DPOR）、Herlihy & Wing 1990（线性一致性）、Jepsen/Knossos。

**KPI 目标**：DPOR 规约后与穷举探索差分一致（不漏 bug）；线性一致性检查器对已知正/反例判定正确。

**任务分解**：
- [x] **T8.1 DPOR 完备性强化**：`prop_dpor_diff_ext_test.mbt` 把 oracle 差分推进到
      **顺序敏感**的双领导者竞态场景（失败与否取决于投递交织），随机种子/规模
      扩样断言 DPOR 与穷举结论一致且失败凭据可精确重放。
- [x] **T8.2 故障注入丰富化**：新增 `DiskFault(lose)` 磁盘丢写建模（对标
      TigerBeetle VOPR 存储故障），含确定性/编解码往返/静止态持久性不变量
      违例的最小反例 shrink（`prop_disk_fault_test.mbt`）；拜占庭/时钟漂移既有。
- [x] **T8.3 线性一致性检查器**：`prop_lin_corpus_test.mbt` 对标 Knossos 补齐
      Herlihy & Wing 正/反例语料（并发重叠双向线性化、stale read、future read）
      + 按构造可线性历史/幽灵读变异的 100 迭代差分 PBT。

**依赖与风险**：无外部依赖。

---

### 方向十 · Actor_Framework（Actor 框架）— 对标 Erlang/OTP / Akka

**当前定位**：ActorId/Mailbox/ActorRef、spawn/send/stop、ask 请求-响应、监督、确定性串行调度。
spec 曾声明纯内存确定性模型（不接真并发/async）——**本纲领突破该非目标**。

**对标标杆 / 论文**：Erlang/OTP、Akka、Pony、Actix；
Hewitt 1973、Agha 1986《Actors》、OTP 监督原则。

**KPI 目标**：监督树三种重启策略语义正确；ask 超时/乱序/关联完整性确定性可验证；
若上游 async 可用则接真异步运行时（对外契约不变）。

**任务分解**（**突破** spec「不接真并发/async」非目标）：
- [x] **T10.1 真·异步运行时（核实收口）** ✅：已实测 `moon add moonbitlang/async@0.20.1` 可登记，
      但该库**仅支持 native/LLVM 后端（Linux/macOS）**、且官方标注 experimental/API 不稳定——
      与本仓「三后端（native/wasm-gc/js）全绿」硬门禁冲突，故**维持协作式确定性调度**
      （确定性正是 DST/PBT 证据链的前提）；升级路径：待上游支持 wasm-gc/js 或 API 稳定后，
      以 native-only 条件编译层接入、对外 spawn/send/stop 契约不变。
- [x] **T10.2 监督树语义** ✅：OneForOne/OneForAll/RestForOne + 强度窗口（O(窗口) 修剪），风暴基准 685k events/sec、17087 次重启全恢复。
- [x] **T10.3 背压与邮箱策略** ✅：有界邮箱 + 丢弃/阻塞策略（bounded_mailbox.mbt，容量 PBT P25）。
- [x] **T10.4 ask 超时/关联完整性** ✅：超时/乱序响应/关联 id 完整性（ask.mbt，PBT P11 及 e2e）。

**依赖与风险**：**T10.1 受上游 `moonbitlang/async` 可用性约束**——需先核实能否稳定登记；
不可用时以协作式确定性调度逼近，并在文档标注边界与升级路径。

---

## 第 2 章 · 横切质量门禁（贯穿所有方向）

- [ ] 每个生产化 PR 必过 §0.3 统一验证协议（0 告警 + 三后端全绿 + .mbti 只增 + PBT ≥100）。
- [ ] 性能类任务落 `benches/results/` 工件并接回归 guard。
- [x] 每方向 1 份 paper-to-code 追溯文档（§C5）——docs/verification/paper-to-code-directions.md（十方向汇总，逐条论文→代码→测试）+ paper-to-code-advanced.md（CH/JPS/ALT）。
- [x] 负例/边界回归测试随每方向补齐（对应 backlog P0：unreachable/零节点/单节点/重边/负权/不连通）——见 CHAMPIONSHIP_BACKLOG.md 该项证据（undirected/unweighted/directed 三包 edge_cases 测试）。
- [x] 双语 README（中/英）在状态、范围、命令上保持一致（对应 backlog P1）——中文算法目录补齐至 30+3 与英文版对齐。

---

## 第 3 章 · 进度看板（Progress Dashboard）

> 每完成一项即更新；`证据` 列填 PR 链接 / benchmark 工件路径。

| 方向 | 任务 | 状态 | 证据 |
|------|------|------|------|
| 二 Regex | T2.1 字面量预过滤 | ✅ 完成 | bench 20.2×；`benches/results/regex-prefilter-t2.1-native.md` |
| 二 Regex | T2.2 必经串 + AC 多模 | ✅ 完成 | `aho_corasick.mbt`；`prop_ac_prefilter_test.mbt` 差分 PBT |
| 二 Regex | T2.3 引擎自动选择 | ✅ 完成 | `engine_select.mbt`；`prop_engine_select_test.mbt` 差分 PBT |
| 二 Regex | T2.4 对抗性鲁棒回归 | ✅ 完成 | `prop_adversarial_test.mbt` 硬上界 guard |
| 九 Serialization | T9.1 conformance 语料 | ✅ 完成 | `conformance/` 黄金语料；`conformance_test.mbt` |
| 九 Serialization | T9.2 unknown field | ✅ 完成 | `unknown_reencode_test.mbt` 逐字节保真 |
| 九 Serialization | T9.3 跨实现互通 | ✅ 完成 | protobuf 6.33.6 黄金向量逐字节一致 |
| 九 Serialization | T9.4 packed/map | ✅ 完成 | `prop_packed_test.mbt`；conformance packed/map 向量 |
| 三 Codegen | T3.1 pass 流水线+验证器 | ✅ 完成 | `run_to_fixpoint`+`ir_validator.mbt`；合成程序族削减 86.8%（benches/results/codegen-opt-reduction-2026-07-05.md） |
| 三 Codegen | T3.2 优化 pass 扩充 | ✅ 完成 | SCCP/GVN(含 PRE 上提)/CopyProp(含外部输入)/DCE/ConstFold；真实语料 11 内核 40.1%（benches/results/codegen-real-corpus-native-2026-07-05.md） |
| 三 Codegen | T3.3 代价指令选择 | ✅ 完成 | `burs.mbt` BURS 代价最优 tiling + 最大吞噬对照基线 + PBT |
| 一 Mini_Compiler | T1.1 真·wasm 产物 | ✅ 完成 | wat2wasm+V8 真实执行 22/22 与解释器逐字符一致（docs/verification/backend-products-t1.md） |
| 一 Mini_Compiler | T1.2 真·JS 产物 | ✅ 完成 | node 直接执行 22/22 一致；附 INT_MIN/-1 陷阱修复（同上） |
| 一 Mini_Compiler | T1.3 类型推断深化 | ✅ 完成 | 穷尽性/冗余检查（Maranget usefulness + 缺失见证，exhaustive.mbt）+ 行多态记录合一（row_poly.mbt，见证健全 PBT）；let-多态既有 |
| 一 Mini_Compiler | T1.4 字节码优化+诊断 | ✅ 完成 | 常量折叠/DCE/跳转线程化既有（等价 PBT）；新增 render_diagnostic 源码摘录+caret+修复建议（diagnostics_ext.mbt，确定性 PBT） |
| 四 Parser | T4.1 零拷贝输入 | ✅ 完成 | Input 改 String+码元偏移零物化，json 基准 +17.5%~24.8%（benches/results/parser-zero-copy-t41-native-2026-07-05.md） |
| 四 Parser | T4.2 错误消息质量 | ✅ 完成 | 最远失败合并（error_model.mbt）+ megaparsec 同构 render_error（源码行摘录/caret/unexpected/expecting，error_report_test.mbt 5 项锁定） |
| 四 Parser | T4.3 性能基准 | ✅ 完成 | 回溯密集文法 packrat 线性 vs 朴素指数（d=16 时 4004×）+ 确定性计数 guard（benches/results/parser-packrat-trend-t43-native-2026-07-05.md）；另有 BoundedCache O(1) LRU |
| 五 LSP | T5.1 增量同步性能 | ✅ 完成 | RopeDocument（join-based 平衡 rope）单点编辑 O(log N)，16384 行 228×（benches/results/lsp-rope-t51-native-2026-07-05.md），等价性 PBT 三编码锁定 |
| 五 LSP | T5.2 协议完整性 | ✅ 完成 | 既有批处理/取消/成帧 PBT + 新增 $/progress 三态编解码、ProgressTracker 生命周期校验、LSP 保留区 5 错误码（progress.mbt，成帧往返 PBT 100 迭代） |
| 五 LSP | T5.3 能力语义 | ✅ 完成 | definition/completion/hover/diagnostics 与 analyze 互印五性质 PBT（prop_capability_semantics_test.mbt，100 迭代） |
| 六 Build | T6.1 内容寻址缓存 | ✅ 完成 | Action 指纹内容寻址 + BuildLog 命中即跳过；最小重建集三属性（minimality/sufficiency/noop）PBT 锁定 |
| 六 Build | T6.2 关键路径调度 | ✅ 完成 | schedule_critical_path 堆优先列表调度，混合图 makespan 达关键路径下界；顺带 topo_order 邻接表化 72.2→2.28 ms（31.7×）（benches/results/build-cp-schedule-t62-native-2026-07-05.md） |
| 六 Build | T6.3 鲁棒性回归 | ✅ 完成 | validate_build：环/缺失输入/并发写竞争三类确定性报错（robustness.mbt，PBT 100 迭代） |
| 七 Logging | T7.1 真·OTLP 导出器 | ✅ 完成 | 官方 opentelemetry-proto 解码逐字段相等，黄金字节+PBT 锁定（docs/verification/otlp-export-t7.md） |
| 七 Logging | T7.2 OTel 逐字段对齐 | ✅ 完成 | links/status.message 官方解码逐字段相等（docs/verification/otlp-export-t7.md） |
| 七 Logging | T7.3 采样器对标 | ✅ 完成 | 四采样器 + 分布/单调 PBT（src/logging/samplers_test.mbt） |
| 七 Logging | T7.4 高基数性能 | ✅ 完成 | 仿射边际成本 guard + 10k 往返（src/logging/prop_high_cardinality_test.mbt） |
| 八 DST | T8.1 DPOR 完备性 | ✅ 完成 | 顺序敏感竞态差分（src/dst/prop_dpor_diff_ext_test.mbt） |
| 八 DST | T8.2 故障注入丰富化 | ✅ 完成 | DiskFault 丢写 + shrink（src/dst/prop_disk_fault_test.mbt） |
| 八 DST | T8.3 线性一致性检查器 | ✅ 完成 | H&W/Knossos 语料 + 差分 PBT（src/dst/prop_lin_corpus_test.mbt） |
| 十 Actor | T10.1 真·异步运行时 | ✅ 核实收口 | moonbitlang/async@0.20.1 可登记但仅 native（与三后端门禁冲突）且 experimental——维持协作式确定性调度，升级路径已文档化 |
| 十 Actor | T10.2 监督树语义 | ✅ 完成 | OneForOne/OneForAll/RestForOne+强度窗口（O(窗口) 修剪）；风暴基准 685k events/sec、17087 次重启全恢复（benches/results/actor-supervision-storm-native-2026-07-05.md） |
| 十 Actor | T10.3 背压/邮箱策略 | ✅ 完成 | 有界邮箱 DropNew/DropOldest/Fail + 出队摊销 O(1)（benches/results/actor-bounded-mailbox-scaling-native-2026-07-05.md）；10k 吞吐 11.35M msgs/sec |
| 十 Actor | T10.4 ask 完整性 | ✅ 完成 | `ask.mbt` AskBroker 相关 ID+超时；e2e + 匹配/超时 PBT（prop_p12/p13） |
| 横切 | 负例/边界回归 | ✅ 完成 | undirected/unweighted/directed 三包 edge_cases 测试（unreachable/零节点/单节点/重边/负权/不连通） |
| 横切 | 双语文档一致性 | ✅ 完成 | 中文 README 算法目录补齐至 30+3 与英文版对齐 |
| 横切 | paper-to-code 追溯 | ✅ 完成 | docs/verification/paper-to-code-directions.md（十方向）+ paper-to-code-advanced.md（CH/JPS/ALT） |

---

## 第 4 章 · 攻坚顺序（Attack Order）

1. **方向二 Regex T2.1 字面量预过滤** —— 最自包含、最易量化提速、零外部依赖。**（进行中）**
2. **方向九 Serialization T9.1 conformance 语料** —— 互通正确性，且为方向七 OTLP 铺路。
3. **方向三 Codegen T3.1/T3.2 pass 流水线 + 优化** —— 纯 IR 层、强可验证。
4. **方向七 Logging T7.1 真·OTLP 导出器** —— 复用方向九 protobuf 能力。
5. **方向一 Mini_Compiler T1.1/T1.2 真·wasm/js 产物** —— 突破玩具边界。
6. **方向四/五/六/八 依次推进**，各自独立 PR。
7. **方向十 Actor T10.1 真·异步** —— 先核实上游 `moonbitlang/async`，不可用则协作式逼近。
8. **横切收口**：负例回归、paper-to-code、双语文档一致性。

> 顺序原则：先做**零外部依赖、强可验证、可量化**的方向；有依赖关系的（OTLP←protobuf、
> Actor←async）排在被依赖项之后；受上游约束的（async）放最后并预留协作式降级方案。

---

## 第 6 章 · Infra 扩展方向（Infra Expansion Backlog）

> 2026-07-05 新增：在十大方向之外识别出的 Infra 空白版图。每项均沿用第 0 章五条硬判据、
> DoD 与统一验证协议（三后端全绿 + 基准守卫 + 证据工件），逐个做到极致后合入 main。

### E0 · 核心寻路快路径 — 对标 Rust `pathfinding` crate（本库主战场）

- 稠密整数节点 indexed 快路径 ✅ 已落地：`src/unweighted/bfs_indexed.mbt`、
  `src/directed/dijkstra_indexed.mbt`（CSR 邻接 + visited/dist/parent
  全扁平数组 + (dist<<21|node) Int64 编码二叉堆，无哈希无装箱；
  `astar_indexed` 支持可采纳启发式），与泛型 Map 版差分 PBT 150+150+80
  迭代（代价/边数一致 + 路径合法逐边复核）三后端全绿；Rust 对比矩阵
  同款负载（n=1000/deg=16/100 查询）BFS **13.7×**、Dijkstra **4.0×**
  vs 泛型版——对照 2026-06-21 Rust 采集（BFS 1.82ms / Dijkstra 14.30ms）
  从 0.19-0.30× 劣势翻转为 BFS ≈3.1×、Dijkstra ≈1.5× 优于 Rust
  （benches/results/indexed-fast-path-native-2026-07-05.md）。

### E1 · 核心数据结构库 — 对标 Rust `std::collections` / `im`

- B-tree（有序映射，缓存友好分裂/合并）✅ 已落地：`src/infra_ds/btree.mbt`
  （CLRS §18 单趟下降，t=8 节点内二分；插入预分裂、删除预借位/合并），
  与朴素参照差分 PBT 200 迭代三后端全绿；基准 insert+get n=32000 30.2×、
  范围查询 29.2×（benches/results/infra-ds-btree-e1-native-2026-07-05.md）。
- 位图索引（roaring 式压缩）✅ 已落地：`src/infra_ds/roaring.mbt`
  （Chambi et al. 2016，高 16 位分桶 + array/bitmap 两态自适应容器，字级位或/位与），
  与布尔数组参照差分 PBT（成员 200 + 并交 100 迭代）三后端全绿；
  稠密集合并 103×（同上工件）。
- 持久化 HashMap（HAMT）✅ 已落地：`src/infra_ds/hamt.mbt`
  （Bagwell 2001，32 叉每 5 位分片 bitmap+紧凑子数组，insert/remove 路径复制结构共享），
  与朴素参照差分 PBT 200 迭代三后端全绿；持久化插入 n=8000 47×（同上工件）。
- 跳表 ✅ 已落地：`src/infra_ds/skiplist.mbt`
  （Pugh 1990，多层有序链表 p=1/2 几何晋升；层高由自持 xorshift64 种子决定，
  确定性可复现），与朴素参照差分 PBT 200 迭代三后端全绿；insert+get n=32000 15.1×（同上工件）。
- **E1 首轮收官**：四种核心结构（BTreeMap / RoaringBitmap / HamtMap / SkipList）
  均达数量级 baseline 优势、差分 PBT 三后端全绿、0 告警。
- KPI：与朴素实现（排序数组 / 链式散列）比较，插入/查找/范围扫描达数量级级别优势；
  PBT ≥200 迭代与标准 Map/Set 差分逐位一致。

### E2 · 序列化深化 — 对标 protobuf / flatbuffers（衔接方向九）

- varint/zigzag/定长编解码 ✅ 已落地：`src/infra_codec/codec.mbt`
  （protobuf wire format 同构子集：LEB128 varint、zigzag sint64、小端 fixed32/64、
  length-prefixed bytes/string，畸形输入一律 None 不 panic），边界值定向 +
  round-trip PBT 200 迭代（逐值一致 + 流精确耗尽）三后端全绿；吞吐 2.1×、
  传输体积 2.24×/内存 4.47× 压缩（benches/results/infra-codec-varint-e2-native-2026-07-05.md）。
- 零拷贝惰性字段视图 ✅ 已落地：`src/infra_codec/lazy_view.mbt`
  （对标 protobuf lazy parsing / flatbuffers：编码态缓冲上键扫描 +
  LEN O(1) 跳过 + 定点解码，不物化未访问字段，嵌套消息零拷贝子视图；
  畸形/截断一律 None），差分 PBT 200 迭代 + 全 wire type/嵌套/逐字节
  截断定向三后端全绿；稀疏访问（2/32 字段命中）基准 **163×** vs eager
  单趟全量解码（benches/results/infra-codec-lazy-view-e2-native-2026-07-05.md）。
- 模式演化兼容测试 ✅ 已落地：`src/infra_codec/schema_evolution_test.mbt`
  （protobuf 前后兼容语义：旧读者跳过未知字段、新读者缺失字段 None、
  字段重排等价 + 未知字段随机注入差分 PBT 200 迭代、嵌套消息独立演化、
  int32→int64 varint 拓宽），三后端全绿。
- KPI：round-trip 逐字节一致（✅ 已达）；吞吐 + 体积双维度优于朴素字符串序列化（✅ 已达）；稀疏访问数量级优于全量解码（✅ 163×）。

### E3 · 内存/分配基础设施 — 对标 arena / object-pool 模式

- 对象池、arena 分配模式系统化（Actor ctx_cache 常驻复用已开头，推广至 Parser 上下文、
  Codegen 中间数组、CH 工作区等全部热路径）。
- KPI：热路径逐操作分配数归零或常数化，吞吐基准可测提升并入守卫。

### E4 · 并发调度深化 — 对标 Tokio / Erlang BEAM 调度器（衔接方向十）

- 层级定时器轮（timer wheel）✅ 已落地：`src/infra_timer/timer_wheel.mbt`
  （Varghese & Lauck 1987，5 级×64 槽 + 回绕 cascade，schedule/cancel/expire 摊销 O(1)），
  与朴素 O(n) 扫描差分 PBT 200 迭代（逐 tick 到期集合一致）三后端全绿；
  n=16000 基准 281×（benches/results/infra-timer-wheel-e4-native-2026-07-05.md）。
- 工作窃取双端队列 ✅ 已落地：`src/infra_timer/work_stealing.mbt`
  （Chase & Lev 2005 环形缓冲 owner-LIFO/thief-FIFO 摊销 O(1) + 确定性轮转调度器建模），
  无丢失无重复 + 同输入 trace 逐位一致 PBT 120 迭代三后端全绿；n=64000 混合负载 15.1×。
- O(1) 位图优先级就绪队列 ✅ 已落地：`src/infra_timer/priority_sched.mbt`
  （对标 Linux O(1) 调度器：64 级优先级环形 FIFO + 64 位占用位图，
  de Bruijn find-first-set 常数步选级，enqueue/pick_next 严格 O(1)），
  与朴素参照差分 PBT 200 迭代 + 确定性 trace 重放 + 级内 FIFO/边界定向
  三后端全绿；稳态 churn 基准 n=128000 **82.0×** vs 朴素线性扫描
  （benches/results/infra-timer-priority-sched-e4-native-2026-07-05.md）。
- KPI：定时器插入/取消/触发摊销 O(1)（✅ 已达）；调度公平性与确定性 trace 重放 PBT 守卫（✅ 已达）。

### E5 · 可观测性深化 — 对标 OpenTelemetry / HdrHistogram（衔接方向七）

- 分位数 sketch ✅ 已落地：`src/infra_metrics/ddsketch.mbt`
  （Masson et al. VLDB 2019 DDSketch，对数桶 + 几何中点代表值，相对误差 ≤ α 可证明界，
  O(1) 插入、可合并），误差界证明式 PBT 60+40 迭代三后端全绿；
  n=32000 流式 p99 基准 56.1×（benches/results/infra-metrics-ddsketch-e5-native-2026-07-05.md）。
- 定精度直方图 ✅ 已落地：`src/infra_metrics/hdr_histogram.mbt`
  （Gene Tene HdrHistogram：指数段 + 2^p 线性子桶纯位运算索引，相对误差 ≤ 2^-p，
  固定内存），误差界证明式 PBT 60 迭代三后端全绿；n=32000 流式 p99.9 基准 217.8×。
- tracing span 树 ✅ 已落地：`src/infra_metrics/span_tracer.mbt`
  （对标 OpenTelemetry span 管线 + pprof 火焰聚合：活动栈隐式父子
  O(1)/事件，结束点即时结算 total/self 并按名增量聚合，查询与 trace
  规模无关；确定性时钟约定同 DST），与朴素事件回放差分 PBT 200 迭代 +
  嵌套结算/多根/未结束定向三后端全绿；高频聚合查询基准 n=128000
  **66.6×** vs 每查询全量回放
  （benches/results/infra-metrics-span-tracer-e5-native-2026-07-05.md）。
- KPI：sketch 误差界有证明式测试（✅ 已达）；聚合吞吐数量级优于全量排序求分位（✅ 56.1×）；span 树增量聚合数量级优于回放（✅ 66.6×）。

#### E3 已落地批次

- Slab 分配器 + 分代句柄 ✅ 已落地：`src/infra_alloc/slab.mbt`
  （对标 Rust slab / slotmap crate：连续槽位 + 侵入式 free-list，
  alloc/free/get 均 O(1)；32 位代数句柄常数代价 use-after-free 检测），
  与朴素参照差分 PBT 200 迭代 + 分代失效/双重释放/clear 定向 + 稳态
  churn 容量有界守卫三后端全绿；高占用 churn 基准 n=128000 **37.0×**
  vs 线性扫描槽池、3.1× vs Map 句柄
  （benches/results/infra-alloc-slab-e3-native-2026-07-05.md）。
- bump/region arena ✅ 已落地：`src/infra_alloc/arena.mbt`
  （对标 typed-arena / bumpalo：bump 分配 + 稠密下标句柄 + reset O(1)
  批量释放保留容量），与朴素参照差分 PBT 200 迭代 + 200 代稳态零增长
  结构性守卫（capacity 恒定、句柄稠密确定）三后端全绿；每帧临时树吞吐
  1.9×（GC bump 分配本身快，核心价值为零稳态分配 + SoA 稠密索引；
  benches/results/infra-alloc-arena-e3-native-2026-07-05.md）。
- KPI：high-churn 稳态零增长分配 + O(1)/操作（✅ slab churn 守卫 +
  arena 200 代守卫已达）；吞吐数量级 vs 朴素（✅ slab 37.0×）。

### E6 · 文本基础设施 — 对标 xi-editor rope / VS Code piece-table（衔接方向五）

- rope 编辑器内核 ✅ 已落地：`src/infra_text/rope.mbt`
  （Boehm/Atkinson/Plass 1995，Leaf/Concat 二叉树 split/concat 编辑，
  深度超界全量重建 + 相邻小叶合并；UTF-16 码元索引与 LSP 位置编码对齐），
  与朴素字符串整篇重建差分 PBT 200 迭代三后端全绿；百万码元文档 512 次随机
  编辑平衡不变量锁定；65536×512 编辑基准 **34.4×**
  （benches/results/infra-text-rope-myers-e6-native-2026-07-05.md）。
- Myers 增量 diff ✅ 已落地：`src/infra_text/myers_diff.mbt`
  （Myers 1986 §4a 贪心正向 O((N+M)·D) + V 快照回溯最短编辑脚本），
  round-trip PBT 200 迭代 + 与 O(N·M) DP 最小性差分 120 迭代 +
  编辑受限性质（k 变异 ⇒ D ≤ 2k）60 迭代三后端全绿；相似文本 n=4096
  基准 **204.7×** vs 全量 DP（同上工件）。
- 编辑器级索引 ✅ 已落地（批次 2，xi-editor metric 体系）：每节点缓存
  (UTF-16, UTF-8, 换行) 度量（孤立代理项 WTF-8 语义），UTF-8↔UTF-16 偏移
  双向转换 / 行列定位 / 行首偏移均 O(log n)；随机编辑后与朴素全扫描差分
  PBT 200 迭代（含 2B/3B/4B 代理对负载）三后端全绿；1M 码元文档 line_col
  基准 **570×** vs 朴素全扫描（同上工件）。
- piece-table 变体 ✅ 已落地：`src/infra_text/piece_table.mbt`
  （对标 VS Code 文本缓冲线性 piece 变体 / Crowley 1998：original +
  append-only add 缓冲上的 piece 序列，编辑不移动已有字节、O(#pieces)/
  编辑与文档字节数无关），与朴素 String 差分 PBT 250 迭代 + 与 Rope
  交叉差分 100 迭代三后端全绿；100k 文档 ×256 编辑基准 **45.9×** vs
  朴素拼接（benches/results/infra-text-piece-table-e6-native-2026-07-05.md）。
- KPI：百万字符文档随机编辑摊销 O(log n)（✅ 平衡不变量 + 27.2× 已达）；
  与朴素字符串重建差分逐位一致（✅ 已达）；UTF-8/16 索引双向转换编辑器级
  （✅ 570× 已达）。

### 攻坚排序建议（性价比）

1. **E1 数据结构库**（生态基石、零依赖、最易量化）
2. **E4 定时器轮 + 工作窃取**（与 Actor 打通形成完整运行时故事）
3. **E3 arena/池化系统化**（直接抬升全部既有吞吐基准）
4. **E6 rope/piece-table**（LSP 故事闭环）
5. **E2 / E5**（衔接方向九/七的深化，可与其合并推进）

---

## 第 5 章 · 文档变更记录（Doc Changelog）

- **v3**：新增第 6 章 Infra 扩展方向（E1~E6：数据结构库、序列化深化、内存/分配、
  并发调度、可观测性、文本基础设施）及攻坚排序建议。
- **v2（强化版）**：新增五条硬判据表、单任务 DoD、统一验证协议、全局 KPI、每方向作战卡
  （对标工具 + 论文 + KPI + 任务验收 + 依赖风险）、进度看板、攻坚顺序与排序原则。
- **v1**：初版总纲 + 十方向任务雏形 + 突破 spec 教学级非目标的立场声明。
