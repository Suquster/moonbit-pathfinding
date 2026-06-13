# 实现计划（Implementation Plan）：Parser_Combinator 旗舰深化（🟣 档位 3）

## 概述（Overview）

本计划把 `design.md` 的两层架构（L0 代数核心 / L1 运行期引擎 / L2 旗舰示例 + 基准）拆解为一系列**增量、可编码、可验证**的任务。所有任务遵循以下总则：

- **增量而非重写**：既有冻结契约（`types.mbt`/`primitives.mbt` 与 `combinators.mbt` 的 `seq`/`many`/`many1`/`optional` 签名与成功路径行为）一律不破坏（R14）；新能力以新增 `.mbt` 文件提供。
- **依赖顺序**：L0（algebra → derived → lookahead → error_model）→ L1（engine → commit → packrat → left_recursion → streaming）→ L2（json → arith）→ 基准 → 文档 → 发布。
- **属性测试**：每条以 PBT 验证的属性（Property 1~31）各自独立成一个 `*` 可选子任务，统一基于 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`，每条 **≥100 次迭代**，注释标注 `Feature: parser-combinator, Property {n}: {text}` 与 `**Validates: Requirements X.Y**`。
- **三后端与 native**：测试在 `wasm-gc`/`js`/`native` 上运行；凡涉及 native 后端的测试/基准任务，须先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R15.1/R15.4）。
- **仅文档产出约束（本规格环境）**：本文件为规划工件；实际编码任务在执行阶段落地到对应 `.mbt`/`.mbt.md` 文件。

> 标注约定：`- [ ]* X.Y` 为可选子任务（属性/单元/集成测试），可在快速 MVP 时跳过；`- [ ] X.Y` 为必做实现子任务。顶层任务不带 `*`。

---

## 任务（Tasks）

- [x] 1. L0 代数核心层 —— functor / monad / applicative（`algebra.mbt`）
  - [x] 1.1 实现 `algebra.mbt` 核心代数原语
    - 新建 `src/parser_combinator/algebra.mbt`，实现 `pure`（不消费、恒成功、携带值）、`map`（成功施加 `f` 且保持消费量、失败原样透传 `pos`/`expected~` 不调用 `f`）、`bind`（成功在剩余输入上运行 `f(v)` 返回的解析器、失败原样透传不调用 `f`）、由 `bind`/`map` 派生的 `ap`，以及恒失败不消费的 `pfail(expected~)`
    - 严格保留既有 `seq`/`alt`/`many`/`many1`/`optional` 公开签名不变（R1.6/R14.2）
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_
  - [x]* 1.2 编写 Property 1 属性测试（pure 恒成功零消费）
    - **Property 1：pure 恒成功零消费**
    - 基于 `@infra_pbt.holds_for_all`，≥100 迭代；新增至 `algebra_test.mbt`
    - **Validates: Requirements 1.1**
  - [x]* 1.3 编写 Property 2 属性测试（map 保持消费量）
    - **Property 2：map 保持消费量**
    - **Validates: Requirements 1.2**
  - [x]* 1.4 编写 Property 3 属性测试（map/bind 失败透传且不调用续延）
    - **Property 3：map / bind 失败透传且不调用续延**
    - **Validates: Requirements 1.3, 1.5**
  - [x]* 1.5 编写核心代数定律属性测试（Property 4~10）
    - **Property 4：Functor 恒等律**（Validates: Requirements 2.1）
    - **Property 5：Functor 复合律**（Validates: Requirements 2.2）
    - **Property 6：Monad 左单位元律**（Validates: Requirements 2.3, 1.4）
    - **Property 7：Monad 右单位元律**（Validates: Requirements 2.4）
    - **Property 8：Monad 结合律**（Validates: Requirements 2.5）
    - **Property 9：Alternative 左单位元律**（Validates: Requirements 2.6）
    - **Property 10：Alternative 结合律（PEG 有序选择）**（Validates: Requirements 2.7）
    - 每条属性独立成测试函数，复用 `gen_parser`/`gen_input` 生成器，≥100 迭代
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_
  - [x]* 1.6 实现共享生成器 `gen_parser` / `gen_input`
    - 在有限组合子字母表（`pchar`/`satisfy`/`pure`/`pfail`/`map`/`bind`/`alt`/`seq`/`many`）上按受限深度采样产出 `Parser[T]`，配套 `gen_input` 同字符集采样输入；复用 `@infra_pbt.Rng`（种子驱动、三后端一致）
    - 供任务 1.5 及后续 L0 属性测试复用
    - _Requirements: 2.1, 14.4_

- [x] 2. L0 衍生组合子代数（`derived.mbt`）
  - [x] 2.1 实现 `derived.mbt` 衍生组合子
    - 新建 `src/parser_combinator/derived.mbt`，以 L0 原语 + `bind`/`map`/`alt`/`many` 组合实现 `sep_by`/`sep_by1`、`between`、`chainl1`/`chainr1`、`chainl`/`chainr`（空序列产出 `default` 且不消费）、`lazy(thunk)`（构造推迟到首次 `run`，打破递归文法构造期循环）
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
  - [x]* 2.2 编写 Property 11 属性测试（sep_by 家族收集语义）
    - **Property 11：sep_by 家族收集语义**
    - **Validates: Requirements 3.1, 3.2**
  - [x]* 2.3 编写 Property 12 属性测试（between 仅产出主体并消费三段）
    - **Property 12：between 仅产出主体并消费三段**
    - **Validates: Requirements 3.3**
  - [x]* 2.4 编写 Property 13/14 属性测试（chainl1/chainr1 结合性）
    - **Property 13：chainl1 左结合一致**（Validates: Requirements 3.4）
    - **Property 14：chainr1 右结合一致**（Validates: Requirements 3.5）
    - _Requirements: 3.4, 3.5_
  - [x]* 2.5 编写衍生组合子边界单元测试
    - `chainl`/`chainr` 空操作数序列产出 `default` 且零消费（R3.6）；`lazy` 递归文法不发散（R3.7）
    - _Requirements: 3.6, 3.7_

- [x] 3. L0 前瞻与否定前瞻（`lookahead.mbt`）
  - [x] 3.1 实现 `lookahead.mbt`
    - 新建 `src/parser_combinator/lookahead.mbt`，实现 `lookahead(p)`（成功产出 `p` 值且以进入时 `input` 作为剩余输入零消费、失败在进入位置报告 `p` 期望）与 `not_followed_by(p)`（`p` 失败则成功产出 Unit 零消费、`p` 成功则在进入位置失败零消费）
    - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - [x]* 3.2 编写 Property 15 属性测试（前瞻零消费不变量）
    - **Property 15：前瞻与否定前瞻零消费不变量**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**

- [x] 4. L0 错误模型 —— label / 最远失败合并（`error_model.mbt`）
  - [x] 4.1 实现 `error_model.mbt` 期望排序与 label
    - 新建 `src/parser_combinator/error_model.mbt`，实现内部 `FarthestError` 累加器、`merge_farthest`（取 `offset` 较大者，相等则并集去重）、`normalize_expected`（去重 + 字典序排序）、`label`/`<?>`（`p` 在起始位置失败用 `name` 替换期望；已消费≥1 字符后失败则保留原始位置与期望）
    - _Requirements: 5.1, 5.2, 5.3, 5.5_
  - [x] 4.2 精化既有 `alt` 失败诊断为最远失败（`combinators.mbt`）
    - 在保持 `alt` 签名与成功路径行为不变的前提下，用 `merge_farthest` 在分支间归约：报告 `offset` 最大的失败位置，仅合并落在该最远位置的分支期望（去重 + 排序），舍弃较早位置分支期望
    - _Requirements: 6.1, 6.2, 6.3, 14.2_
  - [x] 4.3 校验 `to_path_error` 桥接保持既有语义
    - 确认 `Fail(pos, expected)` → `@core.PathError::InvalidInput`，期望文本取 `normalize_expected` 后的稳定序列（不改既有签名/语义）
    - _Requirements: 5.4, 14.3_
  - [x]* 4.4 编写错误模型属性测试（Property 16~20）
    - **Property 16：失败结构完整性**（Validates: Requirements 5.1）
    - **Property 17：label 位置敏感改写**（Validates: Requirements 5.2, 5.3）
    - **Property 18：期望集合确定性顺序**（Validates: Requirements 5.5）
    - **Property 19：最远失败位置与期望合并不变量**（Validates: Requirements 6.1, 6.2, 6.3, 6.4）
    - **Property 20：错误位置单调性**（Validates: Requirements 6.5）
    - 每条独立成测试函数，≥100 迭代
    - _Requirements: 5.1, 5.2, 5.3, 5.5, 6.1, 6.2, 6.3, 6.4, 6.5_
  - [x]* 4.5 编写 `to_path_error` 桥接单元测试
    - 验证桥接输出携带行列位置与期望文本（R5.4 示例）
    - _Requirements: 5.4_

- [x] 5. 检查点 —— 确保 L0 代数核心层全部通过
  - 确保所有测试通过；如有疑问询问用户。运行三后端套件（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 6. L1 运行期引擎层地基（`engine.mbt`）
  - [x] 6.1 实现 `engine.mbt` —— Grammar / PCtx / Outcome / lift / 运行入口
    - 新建 `src/parser_combinator/engine.mbt`，定义不透明 `Grammar[T]`（内部字段私有）、`priv PCtx`（`farthest`/`memo`/`lr_heads`/`source`/`enable_memo`）、`priv Outcome[T]`（`OOk`/`OFail(committed~)`）；实现 `lift`（`Parser[T]` → `Grammar[T]`）、`Grammar::pure`/`map`/`bind`、运行入口 `run_naive`（不启用 memo）与 `run_packrat`（启用 memo），并实现 `Outcome → ParseResult` 投影（`OFail` → `Fail(ctx.farthest.pos, normalize_expected(...))`，`committed` 不泄漏）
    - _Requirements: 8.4, 14.1, 14.5_

- [x] 7. L1 提交语义与错误恢复（`commit.mbt`）
  - [x] 7.1 实现 `commit.mbt`
    - 新建 `src/parser_combinator/commit.mbt`，实现 `commit`/`cut`（软失败提升为 `OFail(committed=true)`、成功透传）、`choice`（提交感知择一：`OOk` 立即返回；硬失败立即停止并上抛；软失败回溯到分支起点继续；全软失败耗尽返回软失败）、`recover(p, sync, fallback)`（硬失败时登记诊断、扫描至 `sync` 同步点之后以 `fallback` 续解）
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - [x]* 7.2 编写 Property 21/22 属性测试（提交语义）
    - **Property 21：提交感知择一语义**（Validates: Requirements 7.1, 7.2, 7.3）
    - **Property 22：提交透明性**（Validates: Requirements 7.5）
    - _Requirements: 7.1, 7.2, 7.3, 7.5_
  - [x]* 7.3 编写 `recover` 同步恢复单元测试
    - 硬失败后同步到 `sync` 之后继续解析（R7.4 示例，服务 R11.4）
    - _Requirements: 7.4_

- [x] 8. L1 packrat 记忆化（`packrat.mbt`）
  - [x] 8.1 实现 `packrat.mbt`
    - 新建 `src/parser_combinator/packrat.mbt`，定义 `priv MemoKey{node_id, offset}`（derive Eq/Hash）、`priv MemoEntry`（`Cached`/`Evaluating`）；实现 `memoize(g)`（构造期分配唯一 `node_id`，运行期以 `MemoKey` 查 `ctx.memo`：命中返回缓存 `Outcome`、未命中求值后写回，每键至多算一次）；缓存生命周期随 `PCtx` 新建/释放，不同输入互不污染
    - _Requirements: 8.1, 8.2, 8.5_
  - [x]* 8.2 编写 Property 23 属性测试（packrat 与朴素差分一致性）
    - **Property 23：packrat 与朴素差分一致性**
    - 以 `run_packrat` 与 `run_naive` 互为差分参照，≥100 迭代
    - **Validates: Requirements 8.1, 8.2, 8.3**
  - [x]* 8.3 编写 Property 24 属性测试（packrat 缓存隔离）
    - **Property 24：packrat 缓存隔离**
    - **Validates: Requirements 8.5**
  - [x]* 8.4 编写 packrat 入口 smoke 测试
    - 验证调用方无需改文法即可在 `run_packrat`/`run_naive` 间切换（R8.4）
    - _Requirements: 8.4_

- [x] 9. L1 直接左递归 seed-growing（`left_recursion.mbt`）
  - [x] 9.1 实现 `left_recursion.mbt`
    - 新建 `src/parser_combinator/left_recursion.mbt`，定义 `priv LRHead{seed, growing}`；实现 `left_recursive(name, body)`：以 `Evaluating` 占位 + 失败种子打破最左递归无限下钻，迭代增长（新结果消费更多输入则更新种子并重复，否则停止返回最长匹配），基础情形无匹配则返回起始位置失败且不消费；与 packrat 协作（Warth 2008 直接左递归）
    - _Requirements: 9.1, 9.2, 9.3, 9.4_
  - [x]* 9.2 编写 Property 25 属性测试（左递归与 chainl1 差分一致）
    - **Property 25：左递归与 chainl1 差分一致**
    - 以 `chainl1` 为参照实现做差分校验，≥100 迭代
    - **Validates: Requirements 9.1, 9.2, 9.3, 9.5**
  - [x]* 9.3 编写左递归无基础情形边界单元测试
    - 起始位置无可匹配基础情形 → 返回携带起始位置与期望的失败且不消费（R9.4）
    - _Requirements: 9.4_

- [x] 10. L1 流式 / 增量输入（`streaming.mbt`）
  - [x] 10.1 实现 `streaming.mbt`
    - 新建 `src/parser_combinator/streaming.mbt`，定义 `priv StreamSource{chunks, closed}`、`Cursor{source, pos}`（推进返回新游标）、`Step[T]`（`Done(ParseResult)`/`NeedMore((String) -> Step)`）；实现 `Grammar::run_incremental`（已到达数据上推进，不足且未 closed 返回 `NeedMore` 续延；closed 且不满足返回 `Done(Fail)`）与便捷驱动 `drive`
    - _Requirements: 10.1, 10.2, 10.3, 10.4_
  - [x]* 10.2 编写 Property 26 属性测试（流式分段无关性）
    - **Property 26：流式分段无关性**
    - 配套实现分段方式生成器（对完整输入采样随机切点），以一次性喂入为参照，≥100 迭代
    - **Validates: Requirements 10.1, 10.3, 10.5**
  - [x]* 10.3 编写 Property 27 属性测试（需要更多输入而非误报失败）
    - **Property 27：需要更多输入而非误报失败**
    - **Validates: Requirements 10.2**
  - [x]* 10.4 编写流式 EOF 失败边界单元测试
    - closed 且不满足解析器 → `Done(Fail(pos, expected))`，不误报 NeedMore（R10.4）
    - _Requirements: 10.4_

- [x] 11. 检查点 —— 确保 L1 运行期引擎层全部通过
  - 确保所有测试通过；如有疑问询问用户。运行三后端套件（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 12. L2 旗舰示例 —— JSON 解析器（`json.mbt`）
  - [x] 12.1 实现 `json.mbt` 核心解析与打印
    - 新建 `src/parser_combinator/json.mbt`，定义 `Json` 枚举（derive Eq）；以 `alt`/`between`/`sep_by`/`lazy` 实现 `json_parser`（对象/数组/字符串/数值/`true`/`false`/`null`），字符串解码处理全部转义（`\" \\ \/ \b \f \n \r \t \uXXXX`）；实现规范化 `print_json`（规范数值/转义，支撑往返）与顶层入口 `parse_json`（失败返回携带行列与期望的诊断、不产半成品）
    - _Requirements: 11.1, 11.2, 11.3_
  - [x] 12.2 实现 JSON 引擎版与错误恢复
    - 实现 `json_value_grammar`（引擎版，支持 packrat）与 `parse_json_recover`（以 `commit`+`recover`，数组/对象元素硬失败时同步到下一个 `,` 或闭括号继续）
    - _Requirements: 11.4_
  - [x]* 12.3 编写 Property 28 属性测试（JSON 往返）
    - **Property 28：JSON 往返**
    - 配套实现 `gen_json` 生成器（深度受限、字符串含随机转义、数值限定可精确往返区间）；以 `@infra_pbt.round_trip` 实现（沿用既有 `prop_roundtrip_test.mbt` 桥接模式），≥100 迭代
    - **Validates: Requirements 11.1, 11.7**
  - [x]* 12.4 编写 Property 29 属性测试（JSON 转义解码）
    - **Property 29：JSON 转义解码**
    - **Validates: Requirements 11.2**
  - [x]* 12.5 编写 Property 30 属性测试（JSON 语法错误诊断且不产半成品）
    - **Property 30：JSON 语法错误诊断且不产半成品**
    - **Validates: Requirements 11.3**

- [x] 13. L2 旗舰示例 —— 算术表达式求值器（`arith.mbt`）
  - [x] 13.1 实现 `arith.mbt`
    - 新建 `src/parser_combinator/arith.mbt`，定义 `Expr` 枚举（derive Eq）；分层文法 `expr := term (('+'|'-') term)*`、`term := factor (('*'|'/') factor)*`、`factor := base ('^' factor)?`、`base := number | '(' expr ')'`，`+ -`/`* /` 用 `chainl1`（左结合）、`^` 用 `chainr1`（右结合）；实现 `expr_parser`、参照求值器 `eval_expr`、规范 `print_expr`、顶层 `parse_and_eval`
    - 另以 `left_recursive` 表达同一加减层，供 R9.5 差分
    - _Requirements: 11.5, 11.6_
  - [x]* 13.2 编写 Property 31 属性测试（算术求值一致性）
    - **Property 31：算术求值一致性**
    - 配套实现 `gen_expr` 生成器（深度受限、数值限定可精确区间、避免除零）；`parse_and_eval(print_expr(x))` 与 `eval_expr(x)` 一致，≥100 迭代
    - **Validates: Requirements 11.5, 11.6, 11.8**
  - [x]* 13.3 编写算术优先级与结合性黄金样例单元测试
    - 代表性样例：`8-3-2==3`、`2^3^2==512`、`2+3*4==14`（R11.6）
    - _Requirements: 11.6_

- [x] 14. 检查点 —— 确保 L2 旗舰示例全部通过
  - 确保所有测试通过；如有疑问询问用户。运行三后端套件（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）

- [x] 15. 性能基准（`benches/`）
  - [x] 15.1 新增 `benches/parser_json_bench` 基准包
    - 新建 `benches/parser_json_bench/moon.pkg`（导入 `moonbitlang/core/bench` 与 `@parser_combinator`）与 `parser_json_bench.mbt`，对 JSON 解析按递增规模（嵌套深度/数组长度几何增长）分别以 `run_packrat` 与 `run_naive` 计时；输出含机器标识/后端/输入规模/计时统计的工件并落地 `benches/results/`（沿用 `latest-*.json/md` 约定）
    - 运行命令记录于基准文档；native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 12.1, 12.2, 12.3, 12.5_
  - [x] 15.2 新增 `benches/parser_arith_bench` 基准包
    - 新建 `benches/parser_arith_bench/moon.pkg` 与 `parser_arith_bench.mbt`，对算术求值按递增规模（表达式长度几何增长）分别以 `run_packrat` 与 `run_naive` 计时，输出工件同上
    - native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 12.1, 12.2, 12.3, 12.5_
  - [x]* 15.3 接入回归基线 guard 比较
    - 将新运行与已记基线中位数比较，超出声明容差给出可审计失败报告（沿用既有 guard 模式）。已落地基线工件 `benches/results/latest-parser-combinator.{json,md}` 并记录可复现运行命令；与既有 PowerShell guard 脚本模式对齐
    - _Requirements: 12.4_

- [x] 16. 可执行文档与论文可追溯（`README.mbt.md`）
  - [x] 16.1 扩充 `README.mbt.md` 五大主题可执行示例
    - 扩充 `src/parser_combinator/README.mbt.md`，覆盖核心代数、衍生组合子、错误处理、JSON 与算术两个旗舰示例，全部示例须通过 `moon test *.mbt.md`（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
    - _Requirements: 15.3_
  - [x] 16.2 补充 paper-to-code 可追溯与开源对标
    - 在文档与示例注释中标注 Hutton & Meijer 1998、Leijen & Meijer Parsec、Ford 2002 PEG/packrat、Warth 2008 左递归对照；提供与 `parsec`/`megaparsec`/`nom` 的 API 与语义对比（回溯默认、提交语义、错误模型差异），并显式声明本库差异（含仅支持直接左递归、`alt` 失败诊断精化）
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6_

- [x] 17. 向后兼容回归与发布推进（`release.mbt` / `CHANGELOG.md`）
  - [x] 17.1 推进 SemVer 至 0.2.0 并更新 CHANGELOG
    - 在 `src/parser_combinator/release.mbt` 将版本推进至 `0.2.0`（minor，因 `alt` 失败诊断精化为唯一可观察行为变化，属严格信息增益）；在 `src/parser_combinator/CHANGELOG.md` 追加本次旗舰深化条目并显式声明 `alt` 失败位置/期望精化
    - 确认 `release_info_with_gates` 在测试/文档门禁未全绿时令 `release_ready=false`
    - _Requirements: 15.5, 15.6_
  - [x]* 17.2 编写向后兼容回归测试与 mbti 快照校验
    - 验证既有 `Parser[T]`/`ParseResult[T]`/`Input`/`Pos` 及原语/组合子签名与行为不变；更新/校验 `pkg.generated.mbti` 快照（R14.1/14.2/14.5）
    - _Requirements: 14.1, 14.2, 14.5_

- [x] 18. 最终检查点 —— 三后端全绿与发布就绪
  - 确保所有单元/属性测试、`README.mbt.md` 可执行文档在 `wasm-gc`/`js`/`native` 三后端全部通过（native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）；如有疑问询问用户

## 备注（Notes）

- 标注 `*` 的子任务为可选（属性/单元/集成测试），可在快速 MVP 时跳过；核心实现子任务不可标注为可选。
- 每个任务均引用具体需求条款（`_Requirements: X.Y_`）以保证可追溯；属性测试任务额外标注其 `Property N` 与 `**Validates: Requirements X.Y**`。
- 检查点（任务 5/11/14/18）用于在 L0 → L1 → L2 → 发布的边界做增量验证。
- 属性测试 Property 1~31 各自独立成任务，统一基于 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`），每条 ≥100 迭代；Property 32（三后端差分一致性）由 CI 矩阵承载，不在单测内以迭代实现。
- 凡涉及 native 后端的测试/基准/文档校验任务，须先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
- 任务顺序遵循依赖：L0（algebra → derived → lookahead → error_model）→ L1（engine → commit → packrat → left_recursion → streaming）→ L2（json → arith）→ 基准 → 文档 → 发布；既有冻结契约全程不破坏。

## 任务依赖图（Task Dependency Graph）

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.6", "2.1", "3.1", "4.1"] },
    { "id": 2, "tasks": ["1.2", "2.2", "3.2", "4.2", "4.3"] },
    { "id": 3, "tasks": ["1.3", "2.3", "4.4"] },
    { "id": 4, "tasks": ["1.4", "2.4", "4.5"] },
    { "id": 5, "tasks": ["1.5", "2.5", "6.1"] },
    { "id": 6, "tasks": ["7.1", "8.1", "10.1"] },
    { "id": 7, "tasks": ["9.1", "7.2", "8.2", "10.2"] },
    { "id": 8, "tasks": ["7.3", "8.3", "10.3", "9.2", "12.1", "13.1"] },
    { "id": 9, "tasks": ["8.4", "10.4", "9.3", "12.2", "13.2"] },
    { "id": 10, "tasks": ["12.3", "13.3", "15.1", "15.2", "16.1"] },
    { "id": 11, "tasks": ["12.4", "15.3", "16.2", "17.1"] },
    { "id": 12, "tasks": ["12.5", "17.2"] }
  ]
}
```
