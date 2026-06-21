# Changelog —— Regex_Engine（方向二）

本文件记录 **Regex_Engine** 方向（子包 `src/regex_engine`）作为
**独立发布单元**的全部值得关注的变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/spec/v2.0.0.html)。

> 🌐 语言：简体中文为主，标识符 / API 保留英文。
>
> 本方向维护**独立**于仓库根 `CHANGELOG.md` 的版本线（独立 SemVer），
> 与 umbrella 模块 `moon.mod.json` 的版本解耦——主版本号 `0` 表示骨架阶段
> 公共 API 仍可能演进。发布元数据由 `release_info()` 登记为
> `DirectionRelease`（见 `release.mbt`）。

---

## [Unreleased]

### Performance
- `Pattern` 高层搜索 API（`find_all`/`find_iter`/`captures_all`/`replace`/
  `replace_all`/`replace_fn`/`split`/`split_n`/`find_at`）重构为复用**一次性**
  转换的字符数组：新增包内私有 `Program::exec_chars`（在预转换字符数组上执行
  Pike VM）与 `Pattern::find_all_on`，使不重叠枚举不再对每个匹配重复执行
  `input.iter().to_array()`。消除了多匹配输入上 O(匹配数 × 输入长度) 的转换
  热路径（此前 `find_all` 在含 M 个匹配、长度 N 的输入上为 O(M·N)）。公开 API
  签名与匹配语义完全冻结，三后端（wasm-gc/js/native）逐位一致。

## [0.2.0] - 2026-06-12

旗舰深化（flagship deepening）：在 `0.1.0` 骨架之上做**严格向后兼容、旁路扩展**
的旗舰级深化，对标 Google RE2 / Rust `regex` / PCRE。既有公开类型与函数
（`Regex`/`CharClass`/`ClassItem`/`AnchorKind`/`CharSet`/`Match`/`ParseError`/`Nfa`/
`Dfa` 与 `parse_regex`/`print_regex`/`build_nfa`/`to_dfa`/`Nfa::find`/`Dfa::find`/
`find`/`is_match`）签名与语义**冻结**，`ParseError` 枚举**不扩容**；全部新能力以
新增文件 / 新增类型 / 只增方法的方式提供。按 SemVer 做**次版本**推进（新增
向后兼容功能）。

### Added
- 标志与字符类增强：`Flags`（`i`/`m`/`s`）、预定义类 `\d\w\s` → `CharSet`、
  点号集合、`CharSet::union`/`complement`/`case_fold` 集合运算扩展（统一规约为
  区间运算）（新增标志与字符类增强）。
- 富语法树：`Ast`/`AssertKind`，`Ast::of_regex` 子集提升桥与 `print_ast`
  （新增富语法树与子集提升）。
- 新解析器：`parse_pattern` 支持编号 / 命名 `(?<name>...)` / 非捕获 `(?:...)`
  组、惰性量词后缀 `*?`/`+?`/`??`/`{m,n}?`、词边界 `\b`/`\B`、前瞻
  `(?=...)`/`(?!...)`、预定义类与标志（错误映射到既有 `ParseError`，不扩容）
  （新增功能完备解析器）。
- 捕获模型：`Captures`（`group`/`name`/`group_count`，未设置语义）
  （新增捕获与子匹配模型）。
- 程序与执行：Pike VM 指令集 `Inst`、`Program`、`compile_program`（Thompson
  程序化发射）与 `Program::exec`/`Program::is_match`（线程列表 + 捕获寄存器 +
  按 pc 去重 + 优先级 + 断言 / 前瞻求值，线性时间）；并附 `Program::exec_steps`
  线性步数计量（基准 guard 用）（新增 Pike VM 执行引擎）。
- 匹配策略：`MatchKind`（`LeftmostLongest` 默认 / `LeftmostFirst`）
  （新增可选匹配策略）。
- 性能路径：`Dfa::minimize`（Hopcroft 1971）与 `LazyDfa` 惰性按需子集构造
  （新增 DFA 最小化与惰性 DFA）。
- 高层搜索 API：`Pattern::compile` 与 `is_match`/`find`/`captures`/`find_all`/
  `find_iter`/`captures_all`/`replace`/`replace_all`/`split`（替换支持 `$0..$9`、
  `${name}`、`$$` 引用）（新增高层搜索 API）。
- 实战 demo：`demo_email`/`demo_ipv4`/`demo_iso_date`/`demo_number`/`demo_cases`
  （含编号与命名捕获），贯穿可执行文档与基准复用（新增实战正则集）。
- 属性测试：捕获正确性（P3）、贪婪 / 惰性单调性（P4）、匹配策略序关系（P5）、
  零宽不变量与断言判定（P6）、`find_all` 不重叠穷尽终止（P7）、`split`/`replace`
  重建一致性（P8）、预定义类与标志 CharSet 语义（P9），并扩展五路差分一致
  （P2）；每条 ≥100 迭代、三后端一致（新增属性测试覆盖）。
- 基准：`benches/regex_bench` 三路执行（`Nfa::find`/`Dfa::find`/`Program::exec`）
  × 病态 + 真实负载，附确定性回归 guard（线性步数界 + 真实负载匹配计数基线）
  （新增正则性能基准与回归 guard）。
- 可执行文档：`README.mbt.md` 扩充覆盖捕获、惰性量词、零宽断言、字符类标志、
  高层搜索 API 与实战 demo，并显式声明实现边界与 RE2 / Rust `regex` / PCRE 对标
  （新增旗舰能力可执行文档）。

### Changed
- release: 本方向 `regex_engine_version` 自 `0.1.0` 推进至 `0.2.0`；
  `release_info`/`release_info_with_gates` 语义保持不变（版本字符串更新）。

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ 正则语法树解析/打印 + NFA/DFA 构造 + `find` 匹配 + 往返/差分/错误
属性测试 + 可执行文档」的方向骨架基线。

### Added
- 语法树：`Regex` 正则表达式语法树类型，覆盖字面字符 / 拼接 / 择一 /
  重复（`*` `+` `?`）/ 分组等正则子集结构
  （新增正则语法树类型）。
- 解析与打印：`parse_regex`（解析为语法树，非法输入返回含位置的解析错误
  且不构造自动机）与 `print_regex`（round-trip 配套打印器），二者构成
  解析 ↔ 打印往返闭环（新增正则解析器与打印器）。
- 自动机：基于 Thompson 构造的 `NFA` 与子集构造确定化得到的 `DFA`
  （新增 NFA/DFA 自动机构造）。
- 匹配执行：`find` 在输入串上执行匹配并返回匹配区间
  （新增正则匹配执行与匹配区间返回）。
- 属性测试：解析 ↔ 打印往返性质、NFA 与 DFA 匹配结果差分一致性、
  非法输入错误条件性质，跨三后端一致
  （新增往返 / 差分 / 错误属性测试）。
- 可执行文档：覆盖解析、匹配与匹配区间返回的 `*.mbt.md` 端到端样例
  （新增正则可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/regex_engine/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/regex_engine-v0.2.0...HEAD
[0.2.0]: https://github.com/Suquster/moonbit-pathfinding/compare/regex_engine-v0.1.0...regex_engine-v0.2.0
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/regex_engine-v0.1.0
