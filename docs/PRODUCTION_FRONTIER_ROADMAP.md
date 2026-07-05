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
- [ ] **T3.1 Pass 流水线管理器 + IR 验证器**：可组合 pass pipeline，每 pass 前后断言 SSA 良构性。
- [ ] **T3.2 优化 pass 扩充**：常量折叠、DCE、代数化简、强度削减、CSE，均带等价 PBT。
- [ ] **T3.3 基于代价的指令选择**：BURS 动态规划带真实代价模型，输出最小代价覆盖 + 最优性测试。

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
- [ ] **T1.3 类型推断深化**：let-多态泛化/实例化、代数数据类型穷尽性检查、行多态。
- [ ] **T1.4 字节码优化 + 诊断**：常量传播/DCE/跳转线程化（等价 PBT）；类型错误带期望/实际/源位置/修复建议。

**依赖与风险**：wasm 产物的外部执行验证需 wasmtime/Node 可用（CI 可固化为黄金字节对比，外部执行作可选证据）。

---

### 方向四 · Parser_Combinator（解析器组合子）— 对标 `nom` / `megaparsec`

**当前定位**：functor/monad/alternative 定律、packrat 记忆化、直接左递归（seed-growing）、
增量流式解析、错误恢复、有界 packrat 缓存。

**对标标杆 / 论文**：`nom`(Rust)、`megaparsec`(Haskell)、Parsec；
Hutton & Meijer 1998、Ford 2002（PEG/packrat）、Warth et al. 2008（左递归）、Leijen & Meijer（Parsec）。

**KPI 目标**：packrat vs 朴素线性扩展趋势固化为 benchmark；错误消息含最远失败 + 期望集 + 源位置。

**任务分解**：
- [ ] **T4.1 零拷贝/切片输入**：以位置索引而非复制子串推进，降低分配。
- [ ] **T4.2 错误消息质量**：最远失败合并 + 期望集 + 源位置（对标 megaparsec `ParseErrorBundle`）。
- [ ] **T4.3 性能基准**：packrat vs 朴素在递增规模下的复杂度趋势固化为 benchmark 工件。

**依赖与风险**：无外部依赖。

---

### 方向五 · LSP（语言服务器协议）— 对标 `tower-lsp` / `vscode-languageserver`

**当前定位**：JSON-RPC 2.0、Content-Length 成帧（CRLF/LF）、增量文档同步、位置编码（UTF-8/16/32）。

**对标标杆 / 规范**：`tower-lsp`(Rust)、`vscode-languageserver-node`；
LSP 3.17 规范、JSON-RPC 2.0 规范。

**KPI 目标**：长文档增量编辑达对数级更新；协议消息（批处理/取消/进度/错误码）全覆盖 + 成帧往返 PBT。

**任务分解**：
- [ ] **T5.1 增量同步性能**：以 rope / piece-table 把长文档单次增量变更从次平方级降到对数级。
- [ ] **T5.2 协议完整性**：批处理、取消（`$/cancelRequest`）、进度、标准错误码全覆盖 + 成帧往返 PBT。
- [ ] **T5.3 能力语义**：定义跳转/补全/诊断的真实语义实现与一致性测试。

**依赖与风险**：无外部依赖；真实编辑器联调作可选证据。

---

### 方向六 · Build_Tool（构建工具）— 对标 Bazel / Buck2 / Ninja

**当前定位**：依赖图拓扑调度、并行波次、指纹增量构建、执行框架、构建日志、provenance。

**对标标杆 / 论文**：Bazel、Buck2、Ninja；Mokhov et al. "Build Systems à la Carte"（2018）。

**KPI 目标**：内容寻址缓存命中即跳过，证明最小重建集正确；关键路径调度缩短总时长。

**任务分解**：
- [ ] **T6.1 内容寻址缓存**：以输入指纹做内容寻址，命中即跳过，证明最小重建集正确。
- [ ] **T6.2 关键路径调度**：波次内按关键路径长度排序缩短总时长，benchmark 证明。
- [ ] **T6.3 鲁棒性回归**：循环依赖、缺失输入、并发竞争的检测与确定性报错。

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
- [ ] **T7.2 OTel 语义逐字段对齐**：span 属性/事件/链接/状态/资源与 OTel 数据模型对齐。
- [ ] **T7.3 采样器对标**：父级采样、比例采样、限流采样的确定性实现与分布 PBT。
- [ ] **T7.4 高基数性能**：大量 span/属性下格式化对总长度线性的 guard。

**依赖与风险**：OTLP 导出依赖方向九 protobuf 能力（先做 T9 再做 T7.1 更顺）。

---

### 方向八 · DST（确定性仿真测试）— 对标 FoundationDB / TigerBeetle / Antithesis

**当前定位**：可执行任务体、模拟网络（延迟/丢包/乱序/分区）、虚拟时钟、不变量/eventually、
确定性重放、DPOR 偏序规约、线性一致性检查、shrink。

**对标标杆 / 论文**：FoundationDB DST、TigerBeetle VOPR、Antithesis；
Flanagan & Godefroid 2005（DPOR）、Herlihy & Wing 1990（线性一致性）、Jepsen/Knossos。

**KPI 目标**：DPOR 规约后与穷举探索差分一致（不漏 bug）；线性一致性检查器对已知正/反例判定正确。

**任务分解**：
- [ ] **T8.1 DPOR 完备性强化**：与穷举探索的差分一致性扩样本，证明规约不漏 bug。
- [ ] **T8.2 故障注入丰富化**：拜占庭/时钟漂移/磁盘故障建模 + 不变量违例最小反例 shrink。
- [ ] **T8.3 线性一致性检查器**：对标 Knossos 的历史可线性化判定，带已知正/反例语料。

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
- [ ] **T10.1 真·异步运行时**：若 `moonbitlang/async` 可登记进 `moon.mod.json`，
      把同步调度替换为真实异步消息循环（对外 spawn/send/stop 契约不变）；否则实现协作式调度逼近。
- [ ] **T10.2 监督树语义**：one-for-one / one-for-all / rest-for-one + 重启强度/周期上限，确定性测试。
- [ ] **T10.3 背压与邮箱策略**：有界邮箱、丢弃/阻塞策略、优先级邮箱。
- [ ] **T10.4 ask 超时/关联完整性**：超时、乱序响应、关联泄漏的确定性建模与 PBT。

**依赖与风险**：**T10.1 受上游 `moonbitlang/async` 可用性约束**——需先核实能否稳定登记；
不可用时以协作式确定性调度逼近，并在文档标注边界与升级路径。

---

## 第 2 章 · 横切质量门禁（贯穿所有方向）

- [ ] 每个生产化 PR 必过 §0.3 统一验证协议（0 告警 + 三后端全绿 + .mbti 只增 + PBT ≥100）。
- [ ] 性能类任务落 `benches/results/` 工件并接回归 guard。
- [ ] 每方向 1 份 paper-to-code 追溯文档（§C5）。
- [ ] 负例/边界回归测试随每方向补齐（对应 backlog P0：unreachable/零节点/单节点/重边/负权/不连通）。
- [ ] 双语 README（中/英）在状态、范围、命令上保持一致（对应 backlog P1）。

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
| 三 Codegen | T3.1 pass 流水线+验证器 | ⬜ 待办 | — |
| 三 Codegen | T3.2 优化 pass 扩充 | ⬜ 待办 | — |
| 三 Codegen | T3.3 代价指令选择 | ⬜ 待办 | — |
| 一 Mini_Compiler | T1.1 真·wasm 产物 | ✅ 完成 | wat2wasm+V8 真实执行 22/22 与解释器逐字符一致（docs/verification/backend-products-t1.md） |
| 一 Mini_Compiler | T1.2 真·JS 产物 | ✅ 完成 | node 直接执行 22/22 一致；附 INT_MIN/-1 陷阱修复（同上） |
| 一 Mini_Compiler | T1.3 类型推断深化 | ⬜ 待办 | — |
| 一 Mini_Compiler | T1.4 字节码优化+诊断 | ⬜ 待办 | — |
| 四 Parser | T4.1 零拷贝输入 | ⬜ 待办 | — |
| 四 Parser | T4.2 错误消息质量 | ⬜ 待办 | — |
| 四 Parser | T4.3 性能基准 | ⬜ 待办 | — |
| 五 LSP | T5.1 增量同步性能 | ⬜ 待办 | — |
| 五 LSP | T5.2 协议完整性 | ⬜ 待办 | — |
| 五 LSP | T5.3 能力语义 | ⬜ 待办 | — |
| 六 Build | T6.1 内容寻址缓存 | ⬜ 待办 | — |
| 六 Build | T6.2 关键路径调度 | ⬜ 待办 | — |
| 六 Build | T6.3 鲁棒性回归 | ⬜ 待办 | — |
| 七 Logging | T7.1 真·OTLP 导出器 | ✅ 完成 | 官方 opentelemetry-proto 解码逐字段相等，黄金字节+PBT 锁定（docs/verification/otlp-export-t7.md） |
| 七 Logging | T7.2 OTel 逐字段对齐 | ⬜ 待办 | — |
| 七 Logging | T7.3 采样器对标 | ⬜ 待办 | — |
| 七 Logging | T7.4 高基数性能 | ⬜ 待办 | — |
| 八 DST | T8.1 DPOR 完备性 | ⬜ 待办 | — |
| 八 DST | T8.2 故障注入丰富化 | ⬜ 待办 | — |
| 八 DST | T8.3 线性一致性检查器 | ⬜ 待办 | — |
| 十 Actor | T10.1 真·异步运行时 | ⬜ 待办（依赖上游） | — |
| 十 Actor | T10.2 监督树语义 | ⬜ 待办 | — |
| 十 Actor | T10.3 背压/邮箱策略 | ⬜ 待办 | — |
| 十 Actor | T10.4 ask 完整性 | ⬜ 待办 | — |
| 横切 | 负例/边界回归 | ⬜ 待办 | — |
| 横切 | 双语文档一致性 | ⬜ 待办 | — |

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

## 第 5 章 · 文档变更记录（Doc Changelog）

- **v2（强化版）**：新增五条硬判据表、单任务 DoD、统一验证协议、全局 KPI、每方向作战卡
  （对标工具 + 论文 + KPI + 任务验收 + 依赖风险）、进度看板、攻坚顺序与排序原则。
- **v1**：初版总纲 + 十方向任务雏形 + 突破 spec 教学级非目标的立场声明。
