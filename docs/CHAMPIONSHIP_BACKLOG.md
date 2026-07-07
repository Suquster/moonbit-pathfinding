# Championship Backlog

## INFRA Gap Backlog（2026-07-07 严厉审视 · 补全 / 补广 / 补深）

> 对标 Rust/Go 一线生态的缺口分析。原则：先补深自家最浅的包（最易被评委戳穿），
> 再补高感知度的生态空白；不撒新包摊薄质量。
> 完成标准与本文档一致：仓库内存在代码 + 测试 + 文档 / CI 证据才算完成。

### A. 补深 —— 现有包太浅，优先充实（自家短板）

- [x] A1 `infra_codec`：CBOR（RFC 8949，含深度限制 / 规范编码）、hex
      （RFC 4648）、严格 UTF-8（RFC 3629）已落地（2026-07-07，31 测试）。
- [x] A2 `infra_text`：字素簇（UAX #29 子集）、显示宽度（wcwidth/UAX #11）、
      大小写折叠已落地（2026-07-07，32 测试）。
- [x] A3 `infra_ds`：B 树 / 跳表 / HAMT / Roaring 已有；BloomFilter（K-M 双
      哈希）+ LRU（O(1) 槽位链表，参考模型 PBT）已补（2026-07-07，25 测试）。
- [x] A4 复盘：`infra_metrics` 已有 HDR 直方图 + DDSketch + span tracer，
      无需重复建设（审计确认 2026-07-07）。
- [x] A5 清理：`backend_cli` 补管线冒烟测试（2）；`core` 补 DSU/PQueue/
      Weight/PBT 测试（12）（2026-07-07）。

### B. 补广 —— 生态空白新包（每个都是别的语言"装个包就有"）

- [x] B1 新包 `infra_time`：Hinnant 公历算法双射、ISO-8601/RFC 3339 解析
      （含偏移归一化）、时长运算、星期（2026-07-07，9 测试）。
- [x] B2 新包 `infra_hash`：SHA-256（FIPS 180-4）、HMAC（RFC 4231 向量）、
      CRC-32、FNV-1a 32/64（2026-07-07，6 测试）。
- [x] B3 新包 `infra_cli`：POSIX/GNU flag 语义、子命令、`--` 终止符、
      help 生成（2026-07-07，8 测试）。
- [x] B4 新包 `infra_compress`：DEFLATE（RFC 1951：stored/fixed/dynamic 三块型
      inflate + LZ77 哈希链 deflate）与 gzip（RFC 1952：CRC-32 / ISIZE 校验），
      CPython zlib 黄金向量 + 200 迭代 PBT round-trip（2026-07-07，9 测试）。
- [x] B5 CSV / TOML / INI：CSV（RFC 4180）已落地（2026-07-07）；新包
      `infra_config`：TOML 核心子集（toml.io v1.0.0：字符串四形态/四进制整数/
      浮点/布尔/日期时间原文/数组/内联表/[table]/[[array-of-tables]]/点分键）
      与 INI（configparser 语义）（2026-07-07，8 测试）。
- [x] B6 新包 `infra_resilience`：指数退避+jitter、Nygard 三态熔断器、
      令牌桶、滑动窗口限流（显式时钟确定性驱动，2026-07-07）。
- [x] B7 新包 `infra_diff`：Myers diff/patch + SemVer 2.0.0（含 §11 优先级链，
      2026-07-07）。

### C. 补深旗舰 —— 做好一个即答辩亮点

- [x] C1 `regex_engine`：Unicode 字符类 + 惰性 DFA（对标 Rust regex 核心卖点）。
  - 证据：惰性 DFA（`lazy_dfa.mbt`，on-the-fly 子集构造 + 预算护栏）与通用类别表
    （`unicode_gc.mbt`）此前已落地；本轮把 `\p{Name}` / `\P{Name}` 记法接入
    `pattern_parser.mbt`（顶层转义 + 字符类内元素 + 否定类），畸形记法
    （缺花括号 / 未闭合 / 未知类别名）显式报错。端到端测试
    `unicode_class_syntax_test.mbt`（`Pattern::compile` 全链路匹配含非 ASCII）。
    2026-07-07，`moon test -p src/regex_engine` 204/204 绿。
- [x] C2 `actor`：async/await 风格 API 或 mailbox 持久化。
  - 证据：`future.mbt` —— `Future[R]` 句柄（`ask_future` 发起立即返回、
    `await_within` 确定性驱动等待、`poll_result`/`is_ready` 非阻塞轮询、
    `ready`/`map`/`and_then` 组合子），发起与等待解耦支持多请求并发在飞；
    幂等重复 await（结果缓存，不二次消费）。`future_test.mbt` 5 测试；
    2026-07-07，`moon test -p src/actor` 264/264 绿。mailbox 确定性重放此前
    已由 `deterministic.mbt`（`replay_consistent`）覆盖。
- [x] C3 `serialization`：schema 演进 / 版本兼容。
  - 证据：`schema_evolution.mbt` —— wire 级破坏性变更检查器（对标 protobuf
    官方 Updating A Message Type 规则与 Buf breaking 检查）：varint /
    zigzag / I32 / I64 / Len 兼容组、删除必须 reserve、reserved 号名复用、
    singular↔repeated、oneof 归属变化、消息删除，输出结构化
    `BreakingChange` 列表供 CI 门禁。`schema_evolution_test.mbt` 7 测试；
    2026-07-07，`moon test -p src/serialization` 118/118 绿。unknown 字段
    保留重编码（旧读者透传新字段）此前已由 `unknown_reencode_test.mbt` 覆盖。

### D. 补深第二轮 —— 六包体量倍增（2026-07-07 晚，回应"包太薄"审视）

- [x] D1 `infra_hash`：SHA-1（RFC 3174）/ SHA-512（FIPS 180-4）/ MD5
      （RFC 1321 附录 A.5 全套向量）/ xxHash32 / Adler-32（RFC 1950）/
      SipHash-2-4（参考实现向量）/ HMAC-SHA1/512（`hash_family.mbt`）+
      HKDF（RFC 5869 附录 A.1–A.3 官方向量）与 PBKDF2-HMAC-SHA256
      （RFC 7914 §11 向量，80000 迭代）（`kdf.mbt`）。19 测试绿。
- [x] D2 `infra_time`：`Duration`（Go time.Duration 语义：构造/算术/分量/
      `1d2h3m4.500s` 格式化）、`add_months`/`add_years`（java.time 月末
      钳制语义）、ISO 8601 周历（`iso_week_date` 边界年向量）、
      RFC 3339 任意偏移格式化（`time_ext.mbt`）。29 测试绿。
- [x] D3 `infra_cli`：类型化取值 `int_of`/`bool_of`/`float_of`（总体函数）、
      声明式校验 `ValueRule`（required/类型/choices，违例不短路全量汇总，
      clap 风格）、组合短 flag 展开（POSIX guideline 5）（`cli_typed.mbt`）。
      11 测试绿。
- [x] D4 `infra_compress`：动态 Huffman **编码**（RFC 1951 §3.2.7：两遍
      LZ77 频率统计 + 限长(≤15)霍夫曼 + 码长 RLE 16/17/18 + 码长码头）、
      zlib 封装（RFC 1950：CMF/FLG/FCHECK + Adler-32 大端尾，CPython
      黄金向量）（`deflate_dynamic.mbt`）；偏斜数据动态 < fixed 体积见证 +
      200 迭代 PBT。15 测试绿。
- [x] D5 `infra_diff`：unified diff（GNU diff -u hunk 头/上下文合并语义）
      输出、`parse_unified` 解析（畸形显式拒绝）、`apply_unified` 上下文
      校验应用（patch reject 语义）（`unified.mbt`）+ 200 迭代
      format→parse→apply 恒等 PBT。11 测试绿。
- [x] D6 `infra_resilience`：Bulkhead（resilience4j 并发上限+有界队列+
      快速失败）、Hedged requests（Dean & Barroso *The Tail at Scale*：
      发射时刻表/胜者判定/取消语义 + "对冲不慢于单发"不变式 PBT）、
      AIMD 自适应限流（Chiu & Jain 1989）（`resilience_ext.mbt`）。
      11 测试绿。
- 全量口径：2309 测试全绿、acceptance 4 门禁全过（dda95e8 / 1c11d60）。

### E. 补深第三轮 —— 单文件成熟度（2026-07-07 晚，回应"成熟文件应千行级"）

- [x] E1 `infra_hash`：SHA-224 / SHA-384（FIPS 180-4 §6.3/§6.5 官方向量，
      各自独立 IV + 截断输出）、CRC-64/XZ（ECMA-182 反射多项式，
      check 值 0x995DC9BBDF1939FA）、MurmurHash3 x86_32（SMHasher
      参考向量）。23 测试绿。
- [x] E2 `infra_time`：`parse_duration`（Go ParseDuration 风格子集：
      d/h/m/s/ms 递减单位 + 毫秒级小数秒，畸形/乱序/重复显式拒绝，
      与 `Duration::to_string` roundtrip）、`strftime`（POSIX 常用子集
      %Y%m%d%H%M%S%j%a%b%e%%，未知指示符原样保留）。33 测试绿。
- [x] E3 `infra_cli`：`value_or_env` 分层回退（clap `Arg::env` 语义：
      命令行→环境变量→默认值）、`flag_tristate`（GNU `--no-` 否定前缀
      三态）、Damerau–Levenshtein + `suggest_option` did-you-mean
      （git/clap 同款体验）。15 测试绿。
- [x] E4 `infra_diff`：diff3 三方合并（Smith 1988 / git merge-file 语义：
      非重叠自动合并、重叠不一致产出 git 风格冲突标记含 base 段、
      相同修改不算冲突）+ `render_merge` + "ours==base ⇒ 结果==theirs"
      不变式 200 迭代 PBT。16 测试绿。
- [x] E5 `infra_resilience`：计数型滑动窗口错误率熔断 `RateBreaker`
      （resilience4j COUNT_BASED：环形窗口、最少样本数、千分比阈值、
      窗口滑动自动恢复）。13 测试绿。
- [x] E6 `infra_compress`：`deflate_stored`（RFC 1951 §3.2.4 存储块，
      65535 分片 + LEN/NLEN 互补校验，不可压数据零膨胀）、
      `deflate_auto` 块型自动决策（stored/fixed/dynamic 三选一取最小，
      "不劣于任何单编码"120 迭代 PBT）。19 测试绿。
- 全量口径：2332 测试全绿、acceptance 4 门禁全过。

### F. 补深第四轮 —— 生产级 SOTA 对标（2026-07-07 晚）

- [x] F1 `infra_hash`：SHA-3 全家族（FIPS 202：Keccak-f[1600] 24 轮
      θ/ρ/π/χ/ι + 海绵结构 + 0x06/0x80 padding，SHA3-224/256/384/512
      NIST 官方向量 + 跨 rate 多块吸收 CPython 对拍）、BLAKE2b
      （RFC 7693：12 轮 G 函数 + SIGMA 调度 + 参数块 + keyed-MAC +
      变长输出，附录 A 向量 + hashlib 对拍）、CRC-32C（Castagnoli，
      iSCSI/LevelDB/gRPC 同款，check 0xE3069283）、xxHash64
      （Collet 规范，python-xxhash 对拍）（`sha3.mbt`/`blake2b.mbt`）。
      31 测试绿。
- [x] F2 `infra_compress`：LZ4 块格式（lz4.org Block Format：token/
      literals/小端 offset/255 级联长度 + overlap copy + end-of-block
      约束；贪心 4KiB 哈希表压缩器 + 防炸弹 max_out 解压器；
      python-lz4 黄金压缩流可解 + 250 迭代 roundtrip PBT）（`lz4.mbt`）。
      25 测试绿。
- [x] F3 `infra_time`：POSIX TZ 规则（POSIX.1-2017 §8.3：
      `std offset[dst[offset][,start,end]]` + `M月.周.日/时刻` 切换点、
      西正→ISO 东正转换、glibc 两阶段 localtime 折算；美东/中欧/悉尼
      南半球跨年 DST 边界向量）+ RFC 2822 日期格式化（`timezone.mbt`）。
      41 测试绿。
- [x] F4 `infra_diff`：patience diff（Cohen/bzr：唯一公共行锚点 +
      O(n log n) 牌堆 LIS + 递归分治，无锚回退 Myers）+ histogram diff
      （JGit：最低频公共行分割锚），输出与 Myers 同构、与 unified/
      patch 管线完全兼容 + 250 迭代三算法 patch 等价 PBT
      （`histogram.mbt`）。23 测试绿。
- [x] F5 `infra_cli`：bash 补全脚本生成（programmable completion：
      complete -F + COMP_WORDS/compgen + 子命令 case 分派）+ zsh 补全
      （#compdef + _arguments 互斥组 + _describe 子命令状态机），
      clap_complete/cobra 生成器同构（`completion.mbt`）。18 测试绿。
- [x] F6 `infra_resilience`：TIME_BASED 时间型滑动窗口错误率熔断
      （resilience4j/Hystrix rolling window：秒级桶 + 纪元过期）+
      重试预算 RetryBudget（Twitter Finagle：比例存款 20% + 保底
      10/s + ttl 封顶 + tryWithdraw，防重试风暴；重试占比不变式测试）
      （`resilience_ext.mbt`）。18 测试绿。
- 全量口径：2369 测试全绿、acceptance 4 门禁全过。

### 冲刺优先级（截止 2026-07-12 前）

A1 → A2 → B1 → B2 → A5，其余按余量推进。

---

> Search time: 2026-05-31 17:00:00 Asia/Shanghai
> Freshness: realtime-level official contest information, crawled from the 2026 MoonBit Software Synthesis Challenge page.
> Scope: `Suquster/moonbit-pathfinding`

This backlog keeps the project aligned with the official judging model and
turns every discovered gap into a verifiable task. It is intentionally stricter
than a normal TODO list: an item is complete only when code, docs, or CI evidence
exists in the repository.

## Official Scoring Frame

Official contest page: <https://www.moonbitlang.cn/2026-scc>

### Rolling Acceptance

| Dimension | Weight | What must be demonstrable in this repository |
|---|---:|---|
| Completion | 25% | Declared scope builds, runs, and reproduces through commands, examples, and tests. |
| Engineering quality | 25% | Clear module boundaries, maintainable code, tests for key and exceptional paths, consistent error handling. |
| Explainability | 25% | Development article, design rationale, AI-agent usage record, and comparison with adopted open-source references. |
| User experience | 25% | Low-friction install, examples, docs, playground or CLI flows, and AI-agent-friendly usage paths. |

### Final Defense

| Dimension | Weight | Championship interpretation |
|---|---:|---|
| Solves a real problem | 25% | Pathfinding and graph algorithms fill a MoonBit ecosystem gap with realistic use cases. |
| Complete user experience | 25% | README, executable docs, examples, package publishing, and preferably browser playground. |
| Uses MoonBit language strengths | 25% | Generic APIs, multi-backend support, executable Markdown tests, and `moon prove`-ready contracts. |
| Domain knowledge | 25% | Algorithms are grounded in papers, benchmarked, and explained with tradeoffs. |

## Current Baseline

- Package: `Suquster/moonbit-pathfinding` v0.0.1.
- Toolchain observed locally: `moon 0.1.20260427`.
- Baseline before first fix: `moon test` reported 147 passed, 0 failed.
- After first fix: `moon test` reported 150 passed, 0 failed.
- After warning-cleanup pass: fast acceptance reported 151 tests passed, 0
  failed; `moon check` emitted no warnings.
- CI exists with three-backend matrix, coverage, hard-gated docs audit, and release-branch proof evidence jobs.
- Local acceptance entrypoint exists at `scripts/acceptance.ps1`.
- Key risk: authenticated mooncakes publishing, a real browser playground, broader negative/edge regressions, and large real-road benchmark artifacts still need stronger evidence before they can be treated as completed deliverables.

## High-Impact Queue

### P0 - Truthfulness And Verification

- [x] Replace the BFS minimality proof predicate stub with an executable bounded shortest-path check.
  - Evidence: `src/proofs/bfs_proof.mbt`, `src/proofs/bfs_proof_test.mbt`.
  - Verification: `moon test` increased from 147 to 150 tests and passes.
- [x] Remove or harden README / presentation claims that overstated proof, playground, FFI, benchmarks, or advanced algorithms.
  - Evidence: `README.md`, `README.zh-CN.md`, `README.mbt.md`, `docs/presentation/*`, `docs/zh/algorithms/{ch,jps,alt}.md`.
  - Remaining markers are tracked below when they correspond to real future work or environment-gated proof evidence.
- [x] Remove or harden every remaining `stub`, `placeholder`, `TBD`, and `coming soon` claim that affects official scoring.
  - Acceptance: marker scan has no scoring-relevant false claims, or each remaining marker is explicitly scoped as future work.
  - Evidence: `CODE_OF_CONDUCT.md` contact placeholder removed; `lib.mbt` no longer calls itself a placeholder; public package metadata and presentation docs no longer claim unverified `moon prove`, realtime playground, Python FFI, or measured speedups.
- [x] Decide the root package strategy.
  - Current state: `lib.mbt` is intentionally empty and documented as the README doctest anchor.
  - Rationale: implementation packages remain under `src/`; the root package exists so `README.mbt.md` can run as black-box executable documentation without inventing a facade API before MoonBit packaging requirements are settled.
- [x] Convert `moon prove` from best-effort story to the strongest currently supported evidence.
  - Acceptance: runnable command, documented limitations, and at least one proof/predicate artifact that fails on a bad witness.
  - Evidence: `src/proofs/moon.pkg` enables proof mode; `scripts/proof_evidence.ps1` runs `moon test src/proofs`, checks `moon prove --help`, attempts `moon prove src\proofs`, and writes `docs/verification/latest-proof-evidence.{json,md}`. Bad-witness tests are named in `src/proofs/bfs_proof_test.mbt` and `src/proofs/dijkstra_proof_test.mbt`.
  - Verification: `pwsh -File scripts\proof_evidence.ps1` exited 0; runtime predicates reported 35 passed, 0 failed; `moon prove --help` exited 0; static discharge is recorded as `blocked-missing-why3` because Why3 is not on `PATH` on this machine.

### P1 - Official Completion

- [x] Reconcile README claims with implemented scope.
  - Acceptance: every advertised algorithm, backend, benchmark, and example has a command or file path proving it.
  - Evidence: package metadata, README performance section, playground section, and presentation assets now distinguish shipped evidence from planned artifacts; benchmark speed numbers were replaced with artifact requirements.
- [x] Add an official acceptance script.
  - Acceptance: one command runs check, fmt check, tests, README executable docs, docs audit, and coverage gate locally.
  - Evidence: `scripts/acceptance.ps1`.
- [x] Ensure examples are full workflows, not snippets.
  - Acceptance: maze solver, network routing, and eight puzzle each have documented input/output and are covered by tests.
  - Evidence: `examples/maze_solver`, `examples/network_routing`, and `examples/eight_puzzle` are documented runnable packages; `scripts/examples_guard.ps1` executes all three sequentially and checks scenario-specific output markers; `docs/examples/latest-examples-run.{json,md}` and timestamped `docs/examples/examples-run-*.json` artifacts store evidence.
  - Verification: `pwsh -File scripts\examples_guard.ps1` exited 0; maze solver checked 6 markers, network routing checked 5 markers, eight puzzle checked 6 markers.
- [x] Make the package publish-ready.
  - Acceptance: license, README, semver, changelog, package metadata, and mooncakes instructions are internally consistent.
  - Evidence: `moon.mod.json` now points mooncakes to `README.md`, includes repository/homepage/license/keywords/description metadata; `.github/workflows/release.yml` no longer masks publish failures and materializes mooncakes credentials from CI secrets; `scripts/release_guard.ps1` checks metadata, README/changelog/license consistency, workflow hard gates, `moon package`, and `moon publish --dry-run`; `docs/release/latest-release-readiness.{json,md}` stores evidence.
  - Verification: `pwsh -File scripts\release_guard.ps1` exited 0 with `pass-with-warnings`; `moon package` produced `_build\publish\Suquster-moonbit-pathfinding-0.0.1.zip`; `moon publish --dry-run` is blocked locally by missing mooncakes credentials and recorded as an environment warning rather than a false publish claim.

### P1 - Engineering Quality

- [x] Reduce toolchain warnings in core and advanced packages.
  - Acceptance: no deprecated `not(...)`, `.or(...)`, `.size()` usage in maintained source and test code; `moon check` emits no warnings.
  - Evidence: source/test migration to `!expr`, `unwrap_or`, `length`, test-scoped imports, explicit `@double` import, and narrower generic bounds.
  - Verification: `moon check` exited 0 with no warning output; `pwsh -File scripts\acceptance.ps1 -SkipCoverage` exited 0 with 151 tests passed, 5 README doctests passed, `moon doc` passed, and 63/63 public declarations documented.
- [x] Harden CI gates.
  - Acceptance: docs audit is a hard gate, and prove evidence is documented with its Why3/toolchain blocker and upgrade path.
  - Evidence: `.github/workflows/ci.yml` now runs `scripts/audit_doc.ps1` as a hard gate after `moon doc`; the release-branch proof job runs `scripts/proof_evidence.ps1`, records runtime predicate evidence, and preserves the Why3 environment blocker instead of pretending static proof succeeded.
  - Verification: local acceptance runs include `moon doc` plus `scripts/audit_doc.ps1`; the latest release/proof artifacts document the remaining environment-gated proof boundary.
- [x] Add regression tests for negative and edge cases across algorithms.
  - Acceptance: unreachable, invalid graph, zero-node, single-node, duplicate-edge, negative-weight, and disconnected cases are covered where relevant.
  - Evidence: `src/undirected/edge_cases_test.mbt` (Kruskal/Prim/CC/bridges/Hopcroft-Karp/Kuhn-Munkres: empty, single-node, duplicate parallel edges, disconnected forest, non-square matrix), `src/unweighted/edge_cases_test.mbt` (BFS tree: unreachable None, duplicate successors), `src/directed/edge_cases_more_test.mbt` (Yen InvalidK/unreachable, topo empty/single/self-loop cycle, Edmonds-Karp disconnected & source==sink), on top of existing `src/directed/edge_cases_test.mbt` and `src/advanced/edge_cases_test.mbt` (negative-cycle, unknown-node, JPS blocked/forced cases).
- [x] Establish benchmark smoke artifacts.
  - Acceptance: reproducible benchmark JSON or Markdown results with machine, target, input size, and comparison baseline.
  - Evidence: `scripts/benchmark_smoke.ps1`, `benches/results/README.md`, `benches/results/latest-smoke.{json,md}`, and timestamped `benches/results/smoke-wasm-gc-20260531-174841.json`.
  - Verification: `pwsh -File scripts\benchmark_smoke.ps1` exited 0; every benchmark package ran 1 warmup + 5 release iterations on `wasm-gc`.
- [x] Add a benchmark smoke regression guard.
  - Acceptance: a fresh smoke run is compared against checked-in baseline medians without overwriting the baseline, and the guard writes an auditable pass/fail report.
  - Evidence: `scripts/benchmark_guard.ps1`, `benches/results/latest-guard.{json,md}`, and timestamped `benches/results/guard-wasm-gc-20260531-175448.json`.
  - Verification: `pwsh -File scripts\acceptance.ps1 -SkipCoverage -RunBenchmarkGuard` exited 0; BFS, Dijkstra, A*, and Kruskal median deltas were all under the current 50% smoke threshold.
- [x] Upgrade benchmark evidence from smoke timing to lower-noise benchmark/regression gate.
  - Acceptance: native `moon bench` or equivalent harness records algorithm-level timing and compares against checked-in baselines with documented tolerance.
  - Evidence: four `benches/*_bench/*.mbt` packages now keep `moon test` smoke guards and add native `@bench.T` blocks; `scripts/benchmark_native.ps1`, `scripts/benchmark_native_guard.ps1`, `benches/results/latest-native.{json,md}`, `benches/results/latest-native-guard.{json,md}`, and timestamped native artifacts.
  - Verification: `moon bench -p ... --target wasm-gc --release --no-parallelize` reported 4 native benchmarks passed; `pwsh -File scripts\benchmark_native.ps1` generated a native baseline; `pwsh -File scripts\benchmark_native_guard.ps1` exited 0 with all four algorithms under the 25% regression threshold.

### P1 - User Experience

- [x] Turn the playground from TBD into a usable demo or remove the badge until it exists.
  - Acceptance: web demo builds locally and is linked from README, or README no longer implies a ready playground.
  - Evidence: the playground is now live — a wasm-gc browser demo built from `playground/` is auto-deployed to GitHub Pages on every push to `main` (`.github/workflows/pages.yml`), badge and README sections link it, and bridge correctness is test-gated (`playground/solver_test.mbt`).
- [x] Create an AI-agent usage guide.
  - Acceptance: a concise guide shows install, package imports, common calls, and known pitfalls for code agents.
  - Evidence: `docs/AI_AGENT_USAGE.md`, linked from both README files.
- [x] Polish bilingual docs.
  - Acceptance: English and Chinese README files agree on status, scope, and commands.
  - Evidence: README.md and README.zh-CN.md both list the same 37-algorithm catalog (30 classical + 7 frontier) with identical OSM-measured status columns and archived benchmark links (synced 2026-07-05).

### P2 - Championship Differentiators

- [x] Deepen the advanced algorithm trio: CH, JPS, ALT — and beyond.
  - Acceptance: each has implementation, tests, docs, and benchmark story; claims avoid "skeleton" ambiguity.
  - Evidence: production-grade `src/directed/{ch,alt,hub_labels,phast,rphast,many_to_many}.mbt` with real OSM road-network benchmarks (Beijing driving network: CH 46x vs bidirectional Dijkstra at 134 us/query, Hub Labeling 0.44 us/query = 14304x, PHAST one-to-all 6.15x, many-to-many 16-25x, RPHAST 6.9-9.8x, ALT 6.6x), archived in `benches/results/ch-osm-20260705.md` and `benches/results/alt-indexed-osm-20260705.md`; every number is guarded by full-query parity checks against Dijkstra plus differential PBT; paper-to-code traceability extended in `docs/verification/paper-to-code-advanced.md` (sections 4.1-4.6).
- [x] Add paper-to-code traceability.
  - Acceptance: each advanced algorithm doc links assumptions and departures from the source paper to code sections and tests.
  - Evidence: `docs/verification/paper-to-code-advanced.md` — CH (Geisberger 2008) / JPS (Harabor & Grastien 2011) / ALT (Goldberg & Harrelson 2005), paper construct → code lines → tests, plus documented departures (witness budget, uniform-cost JPS); production variants in section 4 add HL / PHAST / RPHAST / many-to-many traceability, and stall-on-demand is now implemented in `src/directed/ch.mbt`.
- [x] Prepare defense assets.
  - Acceptance: slides, script, Q&A, and offline demo all reflect the current repository instead of future plans.
  - Evidence: `docs/presentation/slides.md`, `docs/presentation/video_script.md`, and `docs/rehearsal/qa.md` refreshed (2026-07-05) to cite measured OSM speedups and archived artifacts instead of hedged future-work language; bilingual READMEs list all 38 algorithms with identical status columns (CCH added 2026-07-06, `benches/results/cch-osm-20260706.md`).

## Next Attack Order

1. Keep bilingual READMEs, defense assets, and this backlog in lockstep with new measured evidence (refresh after every capability jump).
2. Optional frontier work: CCH (customizable CH for fast metric swaps), HL label memory compression, nested-dissection contraction order.
3. Re-run and re-archive OSM benchmarks whenever preprocessing or query paths change; never let docs cite stale numbers.

Completed since the original list: edge-case regression suites, OSM real-road benchmark artifacts (Beijing/Xiamen), production-grade CH/ALT/HL/PHAST/RPHAST/m2m with parity+PBT guards, live GitHub Pages playground, radix-heap infrastructure, and the Rust cross-language comparison harness (`bench_rust/`).
