# 生产前沿纲领（Production-Frontier Roadmap）

> 总领性、纲领性文件 · 中文撰写
> 目标（用户主线）：把十大方向**逐个**从「教学/竞赛级」真正捅到**工业生产前沿水平**，
> 对标各领域最顶尖的真实落地实现。
> 执行原则：每个方向一刀真功夫，**带可验证证据（测试 + benchmark）**，独立 PR，
> 不破坏既有公开 API（只增不减），三后端（wasm-gc / native / js）一致。

---

## 0. 总纲（如何判定「触及生产前沿」）

一个方向被判定为「触及生产前沿」，当且仅当**同时**满足：

1. **算法/数据结构对标**：核心数据结构与算法与该领域公认顶尖实现同级（不是骨架、不是占位）。
2. **性能对标**：在可复现 benchmark 上，相对自身朴素基线有**可量化、数量级或显著**的提升，
   且对标实现的关键加速手段已落地（如 SIMD 思想、预过滤、惰性物化、增量计算）。
3. **正确性对标**：以差分一致性 / conformance 语料 / 属性测试（≥100 迭代）证明与
   权威实现**逐位/逐字段等价**。
4. **鲁棒性对标**：覆盖负例、边界、对抗性输入（病态正则、畸形字节、超大输入），无 panic、
   无指数爆炸、无 O(n²) 热路径。
5. **可解释性对标**：paper-to-code 追溯（论文→代码→测试），文档说明与对标实现的取舍差异。

每个方向下分 **当前定位 → 对标标杆 → 生产化任务（带验收）** 三段。
已完成项标 `[x]`，进行中标 `[~]`，待办标 `[ ]`。

---

## 方向二 · Regex_Engine（正则引擎）— 对标 Rust `regex` / RE2

**当前定位**：Thompson NFA + Pike VM + 惰性 DFA + DFA 最小化 + hybrid 切换 + Unicode GC。
算法骨架对标 RE2 思路，但缺少生产引擎最关键的「**不进 VM 就先跳过**」的预过滤层。

**对标标杆**：Rust `regex` / RE2 —— 字面量预过滤（memchr / Teddy 多模匹配）、
必经字面量集（required literal set）、首字节集扫描、多引擎自动选择、惰性 DFA 缓存淘汰。

**生产化任务**：
- [ ] **T2.1 字面量预过滤（literal prefilter）**：从 AST 提取「匹配必经的首字符集 /
      字面量前缀」（保守**超集**，含 case-fold），在 Pike VM 播种前用快速扫描跳到下一个
      候选起点，避免在不可能起点上启动线程。
      *验收*：差分 PBT —— 开/关预过滤对任意生成模式×输入，`find`/`find_all`/`is_match`
      结果逐位相等（≥200 迭代）；benchmark 证明「稀疏命中长文本」场景显著提速。
- [ ] **T2.2 必经字面量集与首字节扫描**：对 `Concat`/`Alt` 提取公共必经子串。
- [ ] **T2.3 引擎自动选择**：依据模式特征（有无捕获、是否定长、字符集规模）在
      Pike VM / 惰性 DFA / 预过滤路径间自动择优，对调用方透明。
- [ ] **T2.4 对抗性鲁棒性回归**：病态正则（`(a*)*`、深嵌套、巨型字符类）步数线性 guard。

---

## 方向九 · Serialization（序列化）— 对标 protobuf / prost

**当前定位**：proto3 wire format（varint/zigzag/定长/LEN）真实正确、Any、流式编解码、
代码生成、JSON 映射、解码错误偏移 + 无部分产物 PBT。

**对标标杆**：Google protobuf C++ / `prost`(Rust) —— 官方 conformance 套件、
跨语言互通、packed repeated、unknown field 保留、proto2/proto3 全特性。

**生产化任务**：
- [ ] **T9.1 protobuf conformance 黄金语料**：引入一组覆盖 wire format 各分支的
      官方对齐测试向量（varint 边界、负数 zigzag、定长、嵌套、packed、unknown），
      以黄金文件回归校验编解码逐字节正确。
      *验收*：黄金语料全绿；新增向量覆盖 ≥ 90% wire 分支；跨三后端逐字节一致。
- [ ] **T9.2 unknown field 保留**：解码保留未知字段并在再编码时原样回写（互通关键）。
- [ ] **T9.3 互通验证**：用真实 protobuf 工具产出的字节做黄金输入（离线固化），证明跨实现互通。

---

## 方向三 · Codegen_Infra（代码生成基础设施）— 对标 LLVM / Cranelift

**当前定位**：SSA、支配树/支配边界、φ 插入、BURS 指令选择、图着色寄存器分配、
线性扫描、合并、GVN、SCCP、liveness。教科书核心齐全。

**对标标杆**：LLVM / Cranelift —— 多 pass 流水线、真实 lowering、调度、窥孔、
基于代价的指令选择、pass 管理器与验证器。

**生产化任务**：
- [ ] **T3.1 Pass 流水线管理器**：可组合的 pass pipeline + 每 pass 前后 IR 验证器断言。
- [ ] **T3.2 更多优化 pass**：常量折叠、死代码消除（DCE）、公共子表达式（已部分）、
      代数化简、强度削减，均带「优化前后求值等价」PBT。
- [ ] **T3.3 基于代价的指令选择**：BURS 动态规划带真实代价模型，输出最小代价覆盖。

---

## 方向一 · Mini_Compiler（迷你编译器）— 对标教学/研究级 ML 编译器

**当前定位**：MiniML 前端 + Algorithm W 类型推断 + 求值 + 栈式字节码 VM +
peephole + TCO。spec 显式声明为玩具/教学语言（不生成原生产物）。

**对标标杆**：OCaml/Haskell 教学实现、《Write You a Haskell》。

**生产化任务**（在 spec 声明边界内做到该层最强）：
- [ ] **T1.1 类型推断深化**：let-多态泛化/实例化、行多态或代数数据类型穷尽性检查的完善。
- [ ] **T1.2 字节码优化深化**：常量传播、死指令消除、跳转线程化，带等价 PBT。
- [ ] **T1.3 诊断质量**：类型错误带期望/实际 + 源位置 + 修复建议（对标 Elm/Rust 诊断）。

---

## 方向四 · Parser_Combinator（解析器组合子）— 对标 nom / megaparsec

**当前定位**：functor/monad/alternative 定律、packrat 记忆化、直接左递归（seed-growing）、
增量流式解析、错误恢复、有界 packrat 缓存。

**对标标杆**：`nom`(Rust) / `megaparsec`(Haskell) / Parsec。

**生产化任务**：
- [ ] **T4.1 零拷贝/切片输入**：以位置索引而非复制子串推进，降低分配。
- [ ] **T4.2 错误消息质量**：最远失败合并 + 期望集 + 源位置（对标 megaparsec 的 `ParseError`）。
- [ ] **T4.3 性能基准**：packrat vs 朴素在递增规模下的复杂度趋势固化为 benchmark 工件。

---

## 方向五 · LSP（语言服务器协议）— 对标 tower-lsp / vscode-languageserver

**当前定位**：JSON-RPC 2.0、Content-Length 成帧（CRLF/LF）、增量文档同步、
位置编码（UTF-8/16/32）。

**对标标杆**：`tower-lsp`(Rust) / `vscode-languageserver-node`。

**生产化任务**：
- [ ] **T5.1 增量同步性能**：长文档单次增量变更次平方级 → 以 rope/piece-table 做到对数级。
- [ ] **T5.2 协议完整性**：批处理、取消、进度、错误码全覆盖 + 成帧往返 PBT。
- [ ] **T5.3 能力扩展**：定义跳转/补全/诊断的真实语义实现与一致性测试。

---

## 方向六 · Build_Tool（构建工具）— 对标 Bazel / Buck2 / Ninja

**当前定位**：依赖图拓扑调度、并行波次、指纹增量构建、执行框架（DryRun/Callback）、
构建日志、provenance。

**对标标杆**：Bazel / Buck2 / Ninja —— 内容寻址缓存、远程缓存协议、最小重建。

**生产化任务**：
- [ ] **T6.1 内容寻址缓存**：以输入指纹做内容寻址、命中即跳过，证明最小重建集正确。
- [ ] **T6.2 关键路径调度**：波次内按关键路径长度排序，缩短总时长，benchmark 证明。
- [ ] **T6.3 循环依赖/缺失输入鲁棒性回归**。

---

## 方向七 · Logging（结构化日志 / 分布式追踪）— 对标 tracing / OpenTelemetry

**当前定位**：事件/span 树/上下文、采样/限流/过滤/脱敏/指标、W3C traceparent、
JSON + logfmt。spec 声明不接真实 I/O / async / 墙钟。

**对标标杆**：`tracing`(Rust) / OpenTelemetry SDK。

**生产化任务**（在内存模型层做到最强）：
- [ ] **T7.1 OTel 语义对齐**：span 属性/事件/链接/状态与 OTel 数据模型逐字段对齐 + 导出格式。
- [ ] **T7.2 采样器对标**：父级采样、比例采样、限流采样的确定性实现与分布 PBT。
- [ ] **T7.3 高基数性能**：大量 span/属性下格式化对总长度线性的 guard。

---

## 方向八 · DST（确定性仿真测试）— 对标 FoundationDB / TigerBeetle DST

**当前定位**：可执行任务体、模拟网络（延迟/丢包/乱序/分区）、虚拟时钟、不变量/eventually、
确定性重放、DPOR 偏序规约、线性一致性检查、shrink。

**对标标杆**：FoundationDB / TigerBeetle / Antithesis 风格 DST。

**生产化任务**：
- [ ] **T8.1 DPOR 完备性强化**：与穷举探索的差分一致性（规约后不漏 bug）扩样本。
- [ ] **T8.2 故障注入丰富化**：拜占庭/时钟漂移/磁盘故障建模 + 不变量违例最小反例 shrink。
- [ ] **T8.3 线性一致性检查器**：对标 Jepsen Knossos 的历史可线性化判定，带已知正/反例。

---

## 方向十 · Actor_Framework（Actor 框架）— 对标 Erlang/OTP / Akka

**当前定位**：ActorId/Mailbox/ActorRef、spawn/send/stop、ask 请求-响应、监督、
确定性串行调度。spec 声明为纯内存确定性模型（不接真并发/网络/async）。

**对标标杆**：Erlang/OTP / Akka / Pony / Actix。

**生产化任务**（在确定性模型层做到 OTP 行为对标）：
- [ ] **T10.1 监督树语义**：one-for-one / one-for-all / rest-for-one 重启策略 +
      重启强度/周期上限，带确定性测试。
- [ ] **T10.2 背压与邮箱策略**：有界邮箱、丢弃/阻塞策略、优先级邮箱。
- [ ] **T10.3 ask 超时/关联完整性**：超时、乱序响应、关联泄漏的确定性建模与 PBT。

---

## 横切 · 质量门禁（贯穿所有方向）

- [ ] 每个方向的生产化 PR 必须：`moon info && moon fmt && moon check`（0 告警）+
      `moon test` 三后端全绿 + 新增 PBT ≥100 迭代 + benchmark 工件落 `benches/results/`。
- [ ] `.mbti` 只增不减（不破坏既有公开 API）。
- [ ] paper-to-code 追溯文档与对标差异说明同 PR 落地。
- [ ] 负例/边界回归测试随每个方向补齐（对应 backlog P0）。

---

## 执行顺序（Attack Order）

1. **方向二 Regex 字面量预过滤（T2.1）** —— 最自包含、最易量化提速、零外部依赖。
2. **方向九 Serialization conformance 语料（T9.1）** —— 互通正确性，竞赛差异化强。
3. **方向三 Codegen pass 流水线 + 优化（T3.1/T3.2）**。
4. 方向四/五/六/七/八/十 依次推进，各自独立 PR。
5. 横切：负例回归、paper-to-code、双语文档一致性随方向同步收口。

> 本文件是活文档：每完成一项即更新勾选并附 PR 链接与 benchmark 证据。
