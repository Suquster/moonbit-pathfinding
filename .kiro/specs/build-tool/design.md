# 技术设计文档（Design Document）

## 概述（Overview）

本设计在已发布的 `build_tool 0.1.0` 骨架之上，做**增量式、严格向后兼容**的旗舰级（🟣 档位 3）深化，目标对标 GNU Make、Ninja、Bazel 与 Buck2 的调度 / 缓存 / 可复现模型。核心原则一句话：**既有公开类型与函数（`Target`/`BuildGraph`/`BuildCache`/`ParseError`/`Cycle` 与 `parse_rules`/`detect_cycle`/`topo_order`/`is_dirty`/`schedule`）的签名、字段与运行时语义一律冻结，所有新能力以旁路扩展（新增类型、新增 `.mbt` 文件、新增函数 / 方法）的方式提供，绝不改写既有最小文法解析、既有调度与脏检查行为。**

本方向**显式声明实现边界**（Requirement 12.4）：Build_Tool 是构建系统的**图与缓存模型层**，停留在「依赖图、调度、增量缓存、溯源记录」这一抽象层——**不**执行真实文件系统读写、**不**派生构建进程、**不**调用编译器。输入指纹（mtime + 内容哈希）、动作（recipe）与 include 源由调用方注入。该边界使核心算法可被属性测试穷尽校验，且 `wasm-gc` / `js` / `native` 三后端行为逐位一致。

既有骨架流水线保持不变：

```
规则文本 ─ parse_rules（冻结，最小文法）──▶ BuildGraph
BuildGraph ─ detect_cycle / topo_order（冻结，复用 @directed）──▶ Cycle? / 拓扑序
BuildGraph ─ schedule（冻结，拓扑分层 + jobs）──▶ 并行批次
Target × BuildCache ─ is_dirty（冻结，mtime + 内容哈希）──▶ Bool
```

旗舰深化在其旁侧新增一条**完整文法 → 富规则模型**流水线，以及内容寻址缓存、最小重建集、增强调度、动态依赖、溯源等旁路能力，并通过「向下投影」（`RuleSet::to_graph`）桥接既有骨架以支撑差分一致性验证：

```
                            ┌────────── 富规则模型（旁路新增）──────────┐
规则文本 ─ parse_rules_full ─▶ RuleSet ── to_graph ──▶ BuildGraph（既有，与 parse_rules 在最小文法子集上一致）
  │  （含 recipe / 变量展开 / 模式规则% / phony / include / 位置诊断）
  │                              │
  └─ parse_rules（冻结，最小文法）─┘
                                 │
  ┌── 内容寻址缓存 ──┐   ┌── 增量与调度增强 ──┐   ┌── 溯源 ──┐
  cache_key / ActionCache    propagate_dirty / minimal_rebuild_set     record_provenance
  serialize_cache / deserialize_cache    critical_path_length / rebuild_schedule    derive_output_hash
                                 add_dynamic_deps / reschedule_with_dynamic
```

旗舰能力分九条主线落地：① 完整规则文法解析（含位置诊断与最小文法向后兼容）；② 内容寻址增量缓存与动作缓存；③ 缓存持久化（序列化往返）；④ 脏传播与最小重建集；⑤ 增量空操作幂等与重建充分性；⑥ 并行调度增强（关键路径 / 确定性 / jobs / 批内独立）；⑦ 动态依赖发现与重新调度；⑧ 可复现与 provenance 溯源；⑨ 端到端 demo、基准与对标。本文档为每条主线给出模块划分、MoonBit 签名级接口、算法说明（paper-to-code）、三后端一致性策略、错误处理与正确性属性。

---

## 架构（Architecture）

### 设计原则与向后兼容契约（Requirement 13）

1. **冻结即契约**：`types.mbt`（`Target`/`BuildGraph`/`BuildCache`/`ParseError`/`Cycle` 及其方法）与 `build_tool.mbt`（`parse_rules`/`detect_cycle`/`topo_order`/`is_dirty`/`schedule`）中现有的 `pub` 声明，其签名、字段与运行时行为一律不改（R13.1/R13.2）。`pkg.generated.mbti` 现有条目保持稳定，新增条目仅追加。
2. **`ParseError` 不扩容**：`ParseError { message : String; line : Int } derive(Eq)` 已被既有 `parse_rules` 与 `Eq` 调用方依赖，**新增列号字段会破坏其 `Eq` 形态与构造点**，故一律不改。旗舰要求的列号级诊断（R2.3）由**新增的旁路错误类型** `GrammarError`（携带 `@parser_combinator.Pos` = 行 / 列 / 偏移）承载，并通过 `GrammarError::to_legacy()` 投影回 `ParseError`（`line` 取 `pos.line`，`message` 内嵌列号），既满足列号诊断又不破坏既有契约（此为刻意取舍，见「设计权衡」）。
3. **既有解析 / 调度 / 脏检查语义不变**：`parse_rules` 继续做「目标 + 依赖边」最小文法解析；`schedule` 继续做拓扑分层 + jobs 切分；`is_dirty` 继续以 mtime + 内容哈希比对。完整文法、内容寻址缓存、最小重建集、关键路径、动态依赖、溯源全部以**新入口**提供。
4. **既有图资产复用而非重写**（R13.3）：`topo_order` / `detect_cycle` 已复用 `@directed.topological_sort`（Kahn）/ `tarjan_scc`（`condensation` 底层）；新增的最小重建集、关键路径、动态依赖重调度继续以 `@directed` 与既有 `schedule` 为底层，不重写已被覆盖的图算法。
5. **infra 复用**（R13.4）：全部新增属性测试复用 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all` / `round_trip`（每条属性 ≥100 迭代）；完整文法解析构建于 `@parser_combinator` 的 `Input` / `Pos` / `Parser` / `satisfy` / `many` / `many1` / `alt` / `seq` / `optional` / `pchar` / `ptoken`；发布元数据复用 `@release_meta`，`release_info` / `release_info_with_gates` 语义不变（R14.5/R14.6）。

### 模块 / 文件划分

下表为 `src/build_tool/` 下的文件规划。**既有文件**保持冻结（仅可追加新方法所需的 import）；**新增文件**承载旗舰能力。

| 文件 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `types.mbt` | 冻结 | 既有核心类型 `Target`/`BuildGraph`/`BuildCache`/`ParseError`/`Cycle` | R13.1 |
| `build_tool.mbt` | 冻结 | 既有 `parse_rules`/`detect_cycle`/`topo_order`/`is_dirty`/`schedule` | R13.2 |
| `release.mbt` | 冻结 / 版本字符串更新 | 发布元数据登记（仅推进 SemVer 字符串） | R14.5/R14.6 |
| `rule_grammar.mbt` | 新增 | 完整规则文法 `parse_rules_full` + `print_rules` + 富模型 `RuleSet`/`Rule`/`Recipe`/`PatternRule`/`GrammarError`，构建于 `@parser_combinator`；含变量展开、模式规则、phony、include、注释、位置诊断 | R1/R2 |
| `cache.mbt` | 新增 | 内容寻址缓存：`content_hash`/`action_fingerprint`/`cache_key`/`ActionCache`；缓存持久化 `serialize_cache`/`deserialize_cache` | R3/R4 |
| `rebuild.mbt` | 新增 | 脏传播与最小重建集 `dirty_targets`/`propagate_dirty`/`minimal_rebuild_set`/`rebuild_schedule`；增量空操作 | R5/R6 |
| `scheduler.mbt` | 新增 | 调度增强：关键路径 `critical_path_length`/`min_layers`（增量增强，既有 `schedule` 冻结复用） | R7 |
| `dynamic.mbt` | 新增 | 动态依赖发现与重新调度 `add_dynamic_deps`/`reschedule_with_dynamic` | R8 |
| `provenance.mbt` | 新增 | 溯源记录 `Provenance`/`record_provenance`/`derive_output_hash` | R9 |
| `demo.mbt` | 新增 | 多模块 C / MoonBit 工程端到端示例 `demo_rules`/`demo_graph` | R10 |
| `README.mbt.md` | 扩充 | 可执行文档覆盖新能力 | R10/R14.3 |
| `CHANGELOG.md` | 扩充 | SemVer 推进记录 | R14.5 |
| `prop_*_test.mbt` | 新增 | 属性测试（见「测试策略」「正确性属性」） | R14.2 |

`benches/` 下新增基准包 `benches/build_tool_bench/`（`build_tool_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`），结构对齐既有 `benches/astar_bench` 等，产出 `benches/results/` 工件并接入 guard（R11）。

### 依赖方向

```
rule_grammar ─┐
              ├─▶ cache ─▶ rebuild ─▶ scheduler
provenance ───┤                    └▶ dynamic
demo ─────────┘
（全部向下依赖既有 types/build_tool；解析依赖 @parser_combinator；
  图算法复用 @directed；测试依赖 @infra_pbt；发布复用 @release_meta）
```

无反向依赖：既有冻结文件不感知任何新增文件；新增文件单向依赖既有模型（`Target`/`BuildGraph`/`BuildCache`）与既有 `schedule`/`detect_cycle`/`topo_order`/`is_dirty`，以及共享叶子包。

---

## 组件与接口（Components and Interfaces）

> 下文签名均为 MoonBit 签名级，遵循既有 `.mbt` / `.mbti` 风格（`pub(all)` 暴露可构造数据，`pub` 暴露只读结构与函数）。边 `(u, v)` 的语义沿用既有约定：「`u` 必须在 `v` 之前构建」，即 `v` 依赖 `u`。

### 4.1 完整规则文法与富模型 `RuleSet`（Requirement 1 / 2）

既有 `parse_rules` 仅识别「目标 + 依赖边」（冻结）。新增富模型承载 recipe、变量、模式规则与 phony，并保留位置诊断。

```moonbit
// rule_grammar.mbt

/// 构建命令（recipe）：不透明命令文本行，保留原始文本以算动作指纹（R1.2）。
pub(all) struct Recipe {
  lines : Array[String]
} derive(Eq, Show)

/// 已展开变量 / 模式后的具体规则（目标 + 依赖 + 可选 recipe）。
pub(all) struct Rule {
  target : String
  deps : Array[String]
  recipe : Recipe
} derive(Eq, Show)

/// 模式规则（pattern rule），如 `%.o: %.c`；'%' 捕获词干 stem 并在实例化时回填（R1.4）。
pub(all) struct PatternRule {
  target_pattern : String          // 含单个 '%'，如 "%.o"
  dep_patterns : Array[String]     // 含 '%'，如 ["%.c"]
  recipe : Recipe
} derive(Eq, Show)

/// 完整规则文法的解析结果（富模型）。
pub(all) struct RuleSet {
  rules : Array[Rule]                  // 具体规则（变量 / 模式已展开），按首次出现稳定排序
  pattern_rules : Array[PatternRule]   // 保留的模式规则（供具体目标匹配实例化）
  variables : Map[String, String]      // name = value 变量表
  phony : Array[String]                // phony 目标名（R1.5）
} derive(Eq, Show)

/// 旗舰列号级解析诊断（旁路新增，不改既有 ParseError）。
pub(all) struct GrammarError {
  pos : @parser_combinator.Pos         // 行 / 列 / 偏移
  expected : Array[String]             // 期望描述
  message : String
} derive(Eq, Show)

/// 投影回既有 ParseError（line 取 pos.line，message 内嵌列号），保后向兼容（R2.3）。
pub fn GrammarError::to_legacy(self : GrammarError) -> ParseError

/// 完整规则文法解析（无 include 解析，include 视作不可解析 → GrammarError）。
pub fn parse_rules_full(src : String) -> Result[RuleSet, GrammarError]

/// 带 include 源注入的完整解析（模型层无真实 FS，include 名 → 源文本由调用方提供，R1.6）。
pub fn parse_rules_full_with_includes(
  src : String, resolve : (String) -> String?
) -> Result[RuleSet, GrammarError]

/// 投影到既有 BuildGraph（节点 + 边），在最小文法子集上与 parse_rules 逐字段一致（R2.4/R2.5）。
pub fn RuleSet::to_graph(self : RuleSet) -> BuildGraph

/// 规范化打印（字段确定性排序），供解析 round-trip 与调试（R1）。
pub fn print_rules(rs : RuleSet) -> String

/// 取目标 recipe（动作指纹来源）。
pub fn RuleSet::recipe_of(self : RuleSet, target : String) -> Recipe?

/// 目标是否为 phony（脏检查恒判需重建，R1.5）。
pub fn RuleSet::is_phony(self : RuleSet, target : String) -> Bool
```

文法（EBNF 概要，构建于 `@parser_combinator`）：

```
ruleset    := (comment | blank | vardef | phonydecl | include | rule)*
vardef     := ident '=' rest_of_line                  // name = value（R1.3）
phonydecl  := '.PHONY' ':' name*                       // phony 目标声明（R1.5）
include    := 'include' ws path                         // 引入另一段规则源（R1.6）
rule       := targets ':' deps recipe_block            // 目标 : 依赖 + 缩进 recipe
targets    := name (ws name)*                           // 名字含模式 '%'（R1.4）
deps       := name*
recipe_block := (TAB command_text NL)*                  // 制表符起始行为 recipe（R1.2）
comment    := '#' rest_of_line                          // 注释（R1.7）
name       := ident_with_pattern                        // 可含 '$(var)' 引用（R1.3）
```

解析期职责：① 形如 `target: dep1 dep2` 登记目标节点、为每依赖生成边 `(dep, target)`、按首次出现去重（R1.1，与 `parse_rules` 一致）；② 缩进行收集为该目标 `Recipe`，原始文本保留（R1.2）；③ 变量定义入 `variables`，目标 / 依赖 / 命令中的 `$(name)` 在解析期展开为值（未定义变量展开为空串，与 Make 一致，R1.3）；④ 模式规则 `%.o: %.c` 入 `pattern_rules`，对具体目标按词干 stem 回填依赖与命令（R1.4）；⑤ `.PHONY` 目标入 `phony`，使 `is_phony` 为真（R1.5）；⑥ `include` 经 `resolve` 取源并**合并入同一 `RuleSet`**，合并后去重规则与单文件一致（R1.6）；⑦ `#` 起始行与空行忽略，不产生节点 / 边（R1.7）；⑧ 任何语法错误返回携带 `Pos`（行 / 列 / 偏移）的 `GrammarError` 且**不构造 `RuleSet`**（R2.1/R2.2/R2.3）。

`print_rules` 以**确定性规范形态**输出（变量按名升序、规则按目标名稳定序、依赖原序、recipe 原文），使 `parse_rules_full(print_rules(rs))` 与 `rs` 等价（解析 round-trip，见正确性属性 1——解析器易错，强制 round-trip 验证）。

**最小文法向后兼容桥**：`RuleSet::to_graph` 把富模型投影为 `BuildGraph`，节点按首次出现去重、边为全部 `(dep, target)`。对仅含「`target: dep1 dep2`、注释、空行」的最小文法文本，`to_graph(parse_rules_full(src))` 与 `parse_rules(src)` 在节点序列与边集合上逐字段一致（R2.4/R2.5，正确性属性 2）。

### 4.2 内容寻址增量缓存与动作缓存（Requirement 3）

```moonbit
// cache.mbt

/// 内容哈希：对输入内容计算的确定性摘要（跨后端一致；纯字符串位运算，不依赖平台）。
pub fn content_hash(content : String) -> String

/// 动作指纹：对 recipe 全部命令行计算的确定性摘要（R1.2 的动作维度）。
pub fn action_fingerprint(recipe : Recipe) -> String

/// 缓存键：由目标名、其全部输入内容哈希（调用方按依赖名升序提供）与动作指纹
/// 复合而成（R3.1）。采用**长度前缀注入式编码**（length-prefixed），使其为
/// 确定性单射——相同输入产相同键、任一分量不同即产不同键（R3.4/R3.6），无需
/// 依赖抗碰撞散列即可作为可证明属性（见「设计权衡」）。
pub fn cache_key(
  target : String, input_hashes : Array[String], action_fp : String
) -> String

/// 动作缓存：缓存键 → 输出内容哈希；命中即跳过该目标重建（R3.2）。
pub(all) struct ActionCache {
  entries : Map[String, String]        // cache_key -> output_hash
}
pub fn ActionCache::new() -> ActionCache
pub fn ActionCache::record(self : ActionCache, key : String, output_hash : String) -> Unit
pub fn ActionCache::hit(self : ActionCache, key : String) -> Bool
pub fn ActionCache::get(self : ActionCache, key : String) -> String?

/// 基于缓存键判定目标是否需重建：命中 → false（排除重建集，R3.2）；
/// 未命中 → true（纳入重建集，R3.3）。
pub fn needs_rebuild_by_key(
  cache : ActionCache, target : String,
  input_hashes : Array[String], action_fp : String
) -> Bool
```

设计要点：① **内容寻址而非时间戳**——缓存键由内容哈希构成，故「内容哈希变化而 mtime 未变」仍判键变化、纳入重建（R3.5，对标 Bazel / Ninja 的内容寻址优于 Make 的纯时间戳）。② **缓存键单射性**——`cache_key` 用长度前缀编码（如 `len(target)|target|n|len(h1)|h1|…|len(fp)|fp`），相同输入字节序列恒得相同键，任一分量改变破坏前缀对齐而得不同键，使 R3.6「确定且内容敏感」成为构造性定理而非概率保证。③ **命中即跳过**——`needs_rebuild_by_key` 是缓存命中正确性（R3.2/R3.3）的单点判定。

### 4.3 缓存持久化（Requirement 4）

```moonbit
// cache.mbt（续）

/// 将 BuildCache 的四张指纹映射序列化为可持久化文本（行式 sections，确定性顺序）。
pub fn serialize_cache(cache : BuildCache) -> String

/// 从文本反序列化重建 BuildCache；格式非法 / 字段缺失返回带行号 ParseError，
/// 且不产部分构造缓存（R4.3）。
pub fn deserialize_cache(text : String) -> Result[BuildCache, ParseError]

/// 按四张映射逐字段比较两份缓存（属性测试与去重判等用）。
pub fn cache_eq(a : BuildCache, b : BuildCache) -> Bool
```

文本格式（行式、确定性、键升序）：

```
# recorded_mtimes
M name mtime
# recorded_hashes
H name hash
# current_mtimes
m name mtime
# current_hashes
h name hash
```

每行以单字符 section 标记起始，键按字典序排序以确保确定性输出。`deserialize_cache` 在遇到未知标记、字段数不符或数值非法时返回 `ParseError(message, line)`（复用既有错误类型，行号即出错行）。由此满足往返：`deserialize_cache(serialize_cache(c))` 与 `c` 四张映射逐字段一致（R4.4，正确性属性 4）。

### 4.4 脏传播与最小重建集（Requirement 5 / 6）

```moonbit
// rebuild.mbt

/// 由缓存计算脏输入集合：is_dirty 为真的目标（既有 is_dirty 冻结复用）。
pub fn dirty_targets(g : BuildGraph, cache : BuildCache) -> Array[Target]

/// 沿依赖边前向传播：脏输入 ∪ 其全部传递下游（前向可达闭包，R5.1）。
pub fn propagate_dirty(g : BuildGraph, dirty_inputs : Array[Target]) -> Array[Target]

/// 最小重建集 = 脏输入及其传递下游目标的并集（R5.2）。等于 propagate_dirty 的结果，
/// 既充分（含全部受影响目标，R5.5）又最小（每元素可由某脏输入到达，R5.6）。
pub fn minimal_rebuild_set(g : BuildGraph, dirty_inputs : Array[Target]) -> Array[Target]

/// 仅对重建集内目标按拓扑序产出调度，重建集外不参与（R5.4）。
pub fn rebuild_schedule(
  g : BuildGraph, dirty_inputs : Array[Target], jobs : Int
) -> Array[Array[Target]]
```

算法：`propagate_dirty` 对脏输入集做**前向可达性遍历**（BFS / DFS），沿边 `(u, v)`（`v` 依赖 `u`）从 `u` 走向 `v`，收集全部可达目标。其结果对充分性（每个受变更传递影响的目标——即从某脏输入前向可达者——必被包含）与最小性（每个被包含目标——必由可达性定义可从某脏输入到达）**同时为真**（R5.5/R5.6，正确性属性 5、6）。`rebuild_schedule` 先取重建集导出子图（仅含重建集内节点与两端皆在集内的边），再复用既有 `schedule` 产出批次，保证仅重建集内目标参与且满足拓扑不变量（R5.4）。

**增量空操作幂等**（Requirement 6）：一次成功构建后调用方对所有目标 `mark_built` 固化基线；若此后无输入变更，则 `dirty_targets` 返回空、`minimal_rebuild_set` 返回空，且连续两次计算均为空且相等（R6.3/R6.5，正确性属性 7）。既有 `is_dirty` 的「干净」判定（当前指纹 == 基线）是该幂等的基础（R6.1）；任一传递依赖变更则其下游经前向传播必被纳入（R6.4，由充分性覆盖）。

### 4.5 并行调度增强：关键路径与确定性（Requirement 7）

既有 `schedule(g, jobs)` 冻结（拓扑分层 + jobs 切分 + nodes 原序稳定输出，已天然满足拓扑不变量、批内独立、确定性、jobs 约束）。旗舰深化**不改 `schedule`**，仅新增关键路径分析并以属性测试固化既有调度的四项不变量。

```moonbit
// scheduler.mbt

/// 关键路径长度：构建图最长依赖链的节点数，等于不限并行度（jobs<=0）下完成
/// 构建所需的最小批次层数（R7.4）。
pub fn critical_path_length(g : BuildGraph) -> Int

/// 不限并行度下完成构建所需的最小批次层数（= critical_path_length；
/// 对无环图等于 len(schedule(g, 0))）。
pub fn min_layers(g : BuildGraph) -> Int
```

算法：`critical_path_length` 在 `topo_order` 给出的拓扑序上做**最长路径 DP**——`longest[v] = 1 + max(longest[u])`（对所有边 `(u, v)`），关键路径长度 = `max_v longest[v]`（O(V+E)）。对无环图，该值等于 `jobs<=0` 时 `schedule` 产出的批次层数（每层剥离入度为 0 节点恰对应一层关键路径推进），故 `critical_path_length(g) == len(schedule(g, 0))`（正确性属性 12 的关键路径分量）。

`schedule` 的四项不变量经属性测试固化：① **拓扑尊重依赖**——批次展平后每目标排在其全部依赖之后（R7.1/R7.5，属性 8）；② **批内独立**——同批任意两目标间无依赖边（R7.6，属性 9）；③ **确定性**——同图同 jobs 两次调度逐元素一致（R7.7，属性 10）；④ **jobs 约束**——`jobs > 0` 时每批长度 ≤ jobs（R7.2，属性 11），`jobs <= 0` 时整层一批（R7.3，示例）。

### 4.6 动态依赖发现与重新调度（Requirement 8）

```moonbit
// dynamic.mbt

/// 为目标追加动态依赖（动作执行后发现，如头文件扫描）：登记缺失节点、
/// 追加边 (dyn_dep, target)，返回新图（不可变，旁路扩展，R8.1）。
pub fn add_dynamic_deps(
  g : BuildGraph, target : Target, dyn_deps : Array[Target]
) -> BuildGraph

/// 并入动态依赖后重新调度（R8.2）；若追加引入依赖环，经 detect_cycle 报告
/// 构成环的目标序列并拒绝产出调度（返回 Err(Cycle)，R8.3）。
pub fn reschedule_with_dynamic(
  g : BuildGraph, target : Target, dyn_deps : Array[Target], jobs : Int
) -> Result[Array[Array[Target]], Cycle]
```

算法：`add_dynamic_deps` 把 `dyn_deps` 中尚未登记的节点追加到 `nodes`、为每个动态依赖 `d` 追加边 `(d, target)`（`d` 须在 `target` 之前），产出新 `BuildGraph`（既有图不变，旁路扩展契约 R13.5）。`reschedule_with_dynamic` 先 `add_dynamic_deps` 再 `detect_cycle`：有环则返回 `Err(Cycle)`（复用既有 `detect_cycle` 基于 `tarjan_scc`，R8.3）；无环则复用既有 `schedule` 重新产出批次。对无环图追加不引入环的动态依赖，并入后仍无环且重新调度满足拓扑不变量（R8.4，正确性属性 14）。

### 4.7 可复现与 provenance 溯源（Requirement 9）

```moonbit
// provenance.mbt

/// 一次构建的溯源记录：目标 + 输入内容哈希（按依赖名升序）+ 动作指纹 + 输出内容哈希。
pub(all) struct Provenance {
  target : String
  input_hashes : Array[String]
  action_fp : String
  output_hash : String
} derive(Eq, Show)

/// 模型层可复现假设：输出内容哈希为输入哈希集合与动作指纹的确定性单射函数
/// （相同输入 + 相同动作 → 相同输出哈希；任一不同 → 不同输出哈希）。
pub fn derive_output_hash(input_hashes : Array[String], action_fp : String) -> String

/// 产出溯源记录（输出哈希由 derive_output_hash 给出）。相同输入与动作恒产生
/// 逐字段一致的记录（R9.1/R9.2/R9.4）；任一不同则记录体现差异（R9.3）。
pub fn record_provenance(
  target : String, input_hashes : Array[String], recipe : Recipe
) -> Provenance
```

设计要点：本方向停留在图与缓存模型层、不执行真实动作，故**可复现性建模为「输出哈希是 (输入哈希, 动作指纹) 的确定性函数」**——这正是 Bazel / Nix 可复现构建的形式化内核（相同输入与动作必得相同输出）。`derive_output_hash` 与 `cache_key` 同样采用长度前缀单射编码，使 R9.4「溯源记录确定」与 R9.3「差异可区分」成为构造性定理（正确性属性 15）。`record_provenance` 内部用 `action_fingerprint(recipe)` 取动作指纹，并对 `input_hashes` 规范升序后参与计算，保证记录确定。

### 4.8 端到端实战 demo（Requirement 10）

```moonbit
// demo.mbt

/// 多模块 C / MoonBit 工程的实战构建规则集（源 → 目标文件 → 库 → 顶层可执行）。
pub fn demo_rules() -> String

/// demo_rules 经 parse_rules 的期望产物（节点集合 + 依赖边集合，供文档断言）。
pub fn demo_graph() -> BuildGraph
```

`demo_rules` 提供贯穿文档与基准的实战规则集（如 `app` 依赖 `libcore.a` 与 `libutil.a`，各库依赖若干 `.o`，各 `.o` 依赖对应 `.c` / `.mbt` 源与共享头），覆盖源文件、目标文件、库与顶层可执行产物的依赖层级（R10.1）。`README.mbt.md` 与基准复用同一规则集，演示 `parse_rules` → `detect_cycle`（无环，R10.3）→ `schedule`（拓扑 + 批内独立，R10.4）→ 单源变更下 `minimal_rebuild_set`（仅含该源下游、相对全量目标数缩减，R10.5）的端到端流程，全部经 `moon test *.mbt.md` 验证（R10.2/R14.3）。

### 4.9 性能基准设计（Requirement 11）

`benches/build_tool_bench/` 覆盖四类工作负载：① **拓扑排序**（`topo_order` 于大规模 DAG）；② **并行调度**（`schedule` 于不同 jobs 与宽 / 深 DAG）；③ **脏检查**（`dirty_targets` / `is_dirty` 于大缓存）；④ **最小重建集**（`minimal_rebuild_set` 于不同脏输入比例）。生成参数化 DAG（链 / 扇出 / 分层网格），输出含机器标识、后端目标、图规模（节点数 / 边数）与计时统计的 JSON / Markdown 工件（R11.2），写入 `benches/results/`；新运行与基线中位数比较、超声明容差给可审计回归报告（R11.3，复用既有 guard 模式）。文档记录可复现运行命令与规模参数（R11.5），并要求 native 后端先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R11.4）。

---

## 数据模型（Data Models）

新增类型一览（既有 `Target`/`BuildGraph`/`BuildCache`/`ParseError`/`Cycle` 不变）：

| 类型 | 文件 | 说明 |
|---|---|---|
| `Recipe` / `Rule` / `PatternRule` | `rule_grammar.mbt` | 构建命令 / 具体规则 / 模式规则 |
| `RuleSet` | `rule_grammar.mbt` | 完整文法富模型（规则 + 模式 + 变量 + phony），投影 `to_graph` |
| `GrammarError` | `rule_grammar.mbt` | 列号级解析诊断（携带 `@parser_combinator.Pos`），投影 `to_legacy` |
| `ActionCache` | `cache.mbt` | 内容寻址动作缓存（缓存键 → 输出哈希） |
| `Provenance` | `provenance.mbt` | 可复现溯源记录（目标 / 输入哈希 / 动作指纹 / 输出哈希） |

**既有 `BuildCache` 复用而非改写**：脏检查继续以四张映射（`recorded_mtimes`/`recorded_hashes`/`current_mtimes`/`current_hashes`）为依据；缓存持久化（`serialize_cache`/`deserialize_cache`）以旁路函数提供，不改 `BuildCache` 结构。**发布元数据**：版本自 `0.1.0` 起按旗舰深化做次 / 主版本推进（R14.5），`release_info` / `release_info_with_gates` 语义不变，仅 `build_tool_version` 字符串与 `CHANGELOG.md` 更新。

---

## 错误处理（Error Handling）

- **既有解析错误（冻结）**：`parse_rules` 继续返回 `ParseError { message, line }`——缺 `:` 分隔符或目标名为空时带 1 起始行号，且不产部分图（R2.1/R2.2 在既有语义内）。
- **完整文法解析错误**：`parse_rules_full` 返回新类型 `GrammarError`（携带 `@parser_combinator.Pos` = 行 / 列 / 偏移 + `expected` 期望描述），任何语法错误**不构造 `RuleSet`**（R2.3）。需要既有形态的调用方经 `GrammarError::to_legacy()` 得 `ParseError`（line = pos.line，列号内嵌 message），保后向兼容。
- **缓存反序列化错误**：`deserialize_cache` 复用 `ParseError`（行式格式，行号即出错行），非法标记 / 字段数不符 / 数值非法返回 `Err` 且不产部分缓存（R4.3）。
- **动态依赖引入环**：`reschedule_with_dynamic` 返回 `Err(Cycle)`（复用既有 `Cycle` 与 `detect_cycle`），承载环节点序列并拒绝调度（R8.3）。
- **无部分产物契约**：解析与反序列化一律「先完整收集后构造」——失败返回 `Err` 而非 `Ok(部分产物)`，与既有 `parse_rules` 的「冒号校验失败即整体返回 `Err`」一致。

---

## 算法说明与 paper-to-code 可追溯（Requirement 12）

| 算法 / 规范 | 来源 | 本库落点 |
|---|---|---|
| rebuilder / scheduler 两维分解 | Mokhov, Mitchell, Peyton Jones《Build Systems à la Carte》 | rebuilder ↔ `rebuild.mbt`（脏传播 / 最小重建集 / 缓存命中）；scheduler ↔ `scheduler.mbt` + 既有 `schedule`（拓扑分层批次） |
| 拓扑序（Kahn 逐层剥离入度 0） | Kahn 1962 | 既有 `topo_order` / `schedule` 复用 `@directed.topological_sort` |
| 强连通分量（环检测） | Tarjan 1972 | 既有 `detect_cycle` 复用 `@directed.tarjan_scc`（`condensation` 底层） |
| DAG 最长路径（关键路径） | DAG 动态规划（拓扑序 DP） | 新 `critical_path_length`（topo 序上 `longest[v]` DP） |
| 内容寻址缓存 | Bazel / Nix / Ninja 内容寻址模型 | 新 `content_hash`/`cache_key`/`ActionCache`（长度前缀单射键） |
| 前向可达传递闭包（脏传播） | 图可达性 | 新 `propagate_dirty`（前向 BFS / DFS 闭包） |
| 可复现构建（输入 + 动作 → 输出确定） | Bazel / Nix 可复现性 | 新 `derive_output_hash`/`record_provenance` |

各新增文件头部以注释标注其对应规范与本设计章节（沿用既有 `build_tool.mbt`/`types.mbt` 的注释风格），实现 paper-to-code 可追溯（R12.1/R12.2）。

---

## 三后端一致性与可移植性（Requirement 14.1 / 14.4）

- **纯整型 / 字符串位运算**：`content_hash`/`action_fingerprint`/`cache_key`/`derive_output_hash` 全程以确定性整型与字符串运算实现（不使用浮点、不依赖平台整型宽度、不依赖哈希表迭代顺序），故 `wasm-gc`/`js`/`native` 三后端逐位一致。
- **键的长度前缀单射编码**：缓存键与输出哈希用长度前缀拼接而非依赖抗碰撞散列，使「相同输入产相同键、任一分量不同产不同键」成为**构造性事实**——三后端无差异，且属性可证。
- **Map 序列化的确定性**：`serialize_cache` 对键**显式升序排序**后输出，规避三后端 `Map` 迭代顺序差异，保证序列化文本确定、往返稳定。
- **复用既有图算法的确定性**：`schedule`/`topo_order`/`detect_cycle` 已以 nodes 原序稳定输出，确定性调度（属性 10）跨后端一致。
- **确定性随机源**：全部属性测试复用 `@infra_pbt` 种子驱动 `Rng`（`rng_new(seed)`），保证三后端逐位一致、可重放，任一后端输出分歧即判构建失败（R14.1）。
- **native 前置**：文档与脚本要求 native 后端运行前 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R11.4/R14.4）。
- **门禁聚合**：三后端测试、属性测试、可执行文档任一未过，`release_info_with_gates` 经 `@release_meta` 聚合阻止本方向进入 release-ready（R14.6）。

---

## 设计权衡与开源对标（Requirement 12.3 / 12.5）

| 维度 | 本库 | GNU Make | Ninja | Bazel | Buck2 |
|---|---|---|---|---|---|
| 增量判定 | 内容哈希 + 动作指纹（可选 mtime） | 时间戳（mtime） | mtime + 命令哈希 | 内容寻址 + 动作摘要 | 内容寻址 + 动作摘要 |
| 调度模型 | 拓扑分层 + jobs 批次（确定性） | 递归 + `-j` | 显式 DAG + 关键路径并行 | 远程并行 + 关键路径 | 远程并行 + 关键路径 |
| 关键路径感知 | 是（`critical_path_length`） | 否 | 是 | 是 | 是 |
| 动态依赖 | 是（`add_dynamic_deps` 重调度） | 部分（`.d` 文件） | 是（`depfile` / `deps`） | 是 | 是 |
| 可复现 / 溯源 | 是（provenance 记录，模型层） | 否 | 否 | 是（action cache / RBE） | 是（action cache） |
| 缓存持久化 | 是（序列化往返） | 否（依赖 FS mtime） | 是（`.ninja_log`） | 是（本地 + 远程） | 是 |
| 规则文法 | 完整子集（变量 / 模式 / phony / include） | 完整（含函数 / 条件） | 极简（生成式） | Starlark | Starlark |

**核心取舍**：与 Bazel / Buck2 同侧——**以内容寻址缓存 + 确定性调度 + 可复现溯源换取最强增量正确性与可审计性**，而非 Make 的「时间戳 + 递归」简易模型。同时保留 Make 风格的可读规则文法（变量 / 模式规则 / phony），在表达力与形式化可验证性之间取平衡。

**实现边界声明（R12.4，显式而非隐式留白）**：
- **不执行真实文件系统读写**：输入指纹（mtime + 内容哈希）由调用方经 `BuildCache::observe` 注入，本库不扫描磁盘。
- **不派生构建进程、不调用编译器**：recipe 以不透明字符串及其指纹建模；「输出」以 `derive_output_hash` 的确定性函数建模，不真正执行命令。
- **include 不做跨文件 FS 解析**：`parse_rules_full_with_includes` 由调用方注入 include 名 → 源文本的 `resolve` 函数（单进程模型）。
- **可复现性是模型层假设**：建模为「输出哈希 = f(输入哈希, 动作指纹)」，对应 Bazel / Nix 的可复现内核，但不验证真实工具链的可复现性。
- 以上边界在 `README.mbt.md` 与本文档显式声明（R12.5）。

---

## 需求可追溯映射（Requirements Traceability）

| 需求 | 设计落点 |
|---|---|
| R1 完整规则文法 | 4.1 `RuleSet`/`parse_rules_full`/`print_rules`（变量 / 模式 / phony / include / 注释 / recipe） |
| R2 位置诊断与最小文法兼容 | 4.1 `GrammarError`/`to_legacy`/`to_graph`（向后兼容桥） |
| R3 内容寻址缓存 | 4.2 `content_hash`/`action_fingerprint`/`cache_key`/`ActionCache` |
| R4 缓存持久化 | 4.3 `serialize_cache`/`deserialize_cache`/`cache_eq` |
| R5 脏传播与最小重建集 | 4.4 `propagate_dirty`/`minimal_rebuild_set`/`rebuild_schedule` |
| R6 增量空操作幂等 | 4.4 `dirty_targets` + 既有 `is_dirty`（幂等与充分性） |
| R7 调度增强 | 4.5 `critical_path_length`/`min_layers` + 既有 `schedule` 不变量 |
| R8 动态依赖 | 4.6 `add_dynamic_deps`/`reschedule_with_dynamic` |
| R9 可复现与 provenance | 4.7 `Provenance`/`record_provenance`/`derive_output_hash` |
| R10 端到端 demo | 4.8 `demo_rules`/`demo_graph` + README |
| R11 性能基准 | 4.9 `benches/build_tool_bench` |
| R12 可解释性 / 对标 | 「算法说明」「设计权衡与开源对标」 |
| R13 向后兼容 | 「设计原则与兼容契约」「模块划分」冻结列；`to_graph`/`to_legacy` 桥 |
| R14 质量门禁 | 「三后端一致性」+ 测试策略 + 正确性属性 |

---

## 测试策略（Testing Strategy）

**双轨测试**：单元测试锁定具体见证与边界 / 错误条件；属性测试以 `@infra_pbt` 覆盖通用不变量（每条 ≥100 迭代，R14.2）。

- **单元测试（示例 / 边界 / 错误）**：
  - 文法具体样例（recipe / 变量展开 / 模式规则 / phony / include 合并）与语法错误位置（缺 `:`、目标名为空，R2.1/R2.2/R2.3）；
  - 缓存键内容敏感边界（mtime 同、内容哈希不同仍重建，R3.5）、缓存命中 / 未命中（R3.2/R3.3）；
  - 缓存反序列化非法格式错误（R4.3）；
  - `is_dirty` 干净 / 脏边界（指纹缺失 / 不一致，R6.1/R6.2）；
  - `jobs<=0` 整层一批（R7.3）、关键路径长度 == 不限并行批次层数（R7.4）；
  - 动态依赖引入环返回 `Err(Cycle)`（R8.3）；
  - 端到端 demo 流程（解析 / 无环 / 调度 / 单源增量重建缩减，R10.2–10.5）；
  - 既有 API 回归（`parse_rules`/`schedule`/`is_dirty` 行为不变，R13.1/R13.2）、`release_info` 稳定与门禁真值表（R14.5/R14.6）。
- **属性测试**：见下「正确性属性」P1–P15，复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`；生成器涵盖随机 `RuleSet`（含变量 / 模式 / phony）、随机最小文法文本、随机 DAG（链 / 扇出 / 分层）、随机脏子集、随机 `BuildCache`、随机输入哈希与动作。
- **基准与冒烟**：`benches/build_tool_bench` 四类负载（R11.1）、工件产出（R11.2）、guard 回归（R11.3）；`README.mbt.md` 经 `moon test *.mbt.md`（R10/R14.3）。
- **三后端**：同一套件在 `wasm-gc`/`js`/`native` 运行，分歧判失败（R14.1）；native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R14.4）。
- **属性测试标注**：统一 `Feature: build-tool, Property {n}: {text}`，并以 `**Validates: Requirements X.Y**` 链接验收标准。

---

## 正确性属性（Correctness Properties）

*属性（property）是对系统在所有合法执行下应恒成立行为的形式化陈述，是人类可读规格与机器可验证保证之间的桥梁。下列属性均以全称量化表述，并复用 `@infra_pbt` 的 `holds_for_all`/`round_trip`（每条 ≥100 迭代）。*

### Property 1：规则解析 round-trip（rule parse round-trip）

*对任意*由生成器产出的合法 `RuleSet` `rs`，先规范打印再解析应得到等价模型：`parse_rules_full(print_rules(rs)) == Ok(rs)`。该属性统摄目标 / 依赖登记与去重、recipe 原始文本保留、变量展开、模式规则词干回填与注释 / 空行忽略的结构保真性（解析器易错，强制 round-trip 验证）。

**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.7**

### Property 2：最小文法向后兼容（minimal-grammar backward compatibility）

*对任意*由生成器产出的合法最小文法规则文本（仅 `target: dep1 dep2`、注释与空行），完整文法解析的图投影与既有最小文法解析在节点序列与依赖边集合上一致：`RuleSet::to_graph(parse_rules_full(src))` 与 `parse_rules(src)` 逐字段相等。

**Validates: Requirements 2.4, 2.5**

### Property 3：缓存键确定且内容敏感（cache-key determinism & content sensitivity）

*对任意*由生成器产出的（目标, 输入内容哈希序列, 动作指纹），`cache_key` 计算确定（相同输入恒产相同键）；且对内容哈希敏感（任一输入内容哈希或动作指纹改变即产不同键）。

**Validates: Requirements 3.1, 3.4, 3.6**

### Property 4：缓存往返一致性（cache serialization round-trip）

*对任意*由生成器产出的 `BuildCache` `c`，序列化后再反序列化得到与原缓存逐字段一致的缓存：`deserialize_cache(serialize_cache(c))` 为 `Ok(c')` 且 `cache_eq(c, c')` 为真（四张指纹映射逐字段相等）。

**Validates: Requirements 4.1, 4.2, 4.4**

### Property 5：最小重建集充分性（rebuild-set sufficiency）

*对任意*由生成器产出的无环构建图与脏输入子集，每个从某脏输入沿依赖边前向可达的目标都被包含在最小重建集中（受变更传递影响的目标无一遗漏）。

**Validates: Requirements 5.1, 5.2, 5.5, 6.4**

### Property 6：最小重建集最小性（rebuild-set minimality）

*对任意*由生成器产出的无环构建图与脏输入子集，最小重建集中的每个目标都可由某脏输入沿依赖边到达（不含任何未受影响目标）。

**Validates: Requirements 5.3, 5.6**

### Property 7：增量空操作幂等（incremental no-op idempotence）

*对任意*由生成器产出的构建图与缓存状态，当所有目标的当前指纹与基线指纹一致（无输入变更）时，连续两次计算的最小重建集均为空且彼此相等。

**Validates: Requirements 6.1, 6.3, 6.5**

### Property 8：调度尊重依赖（schedule respects dependencies）

*对任意*由生成器产出的无环构建图，`schedule` 产出的批次序列展平后，每个目标都排在其全部依赖之后（拓扑不变量）。

**Validates: Requirements 7.1, 7.5**

### Property 9：批内独立（intra-batch independence）

*对任意*由生成器产出的无环构建图，`schedule` 产出的同一并行批次内任意两个目标之间不存在依赖边。

**Validates: Requirements 7.6**

### Property 10：调度确定性（scheduling determinism）

*对任意*由生成器产出的无环构建图与同一 `jobs`，两次调用 `schedule` 产出逐元素一致的批次序列。

**Validates: Requirements 7.7**

### Property 11：并行度约束（jobs-bound respected）

*对任意*由生成器产出的无环构建图与 `jobs > 0`，`schedule` 产出的每个并行批次的目标数都不超过 `jobs`。

**Validates: Requirements 7.2**

### Property 12：关键路径等于最小批次层数（critical-path equals minimal layers）

*对任意*由生成器产出的无环构建图，关键路径长度等于不限并行度（`jobs <= 0`）下完成构建所需的批次层数：`critical_path_length(g) == len(schedule(g, 0))`。

**Validates: Requirements 7.3, 7.4**

### Property 13：环检测可靠性（cycle-detection reliability）

*对任意*由生成器产出的构建图，`detect_cycle` 返回 `Some(环节点序列)` 当且仅当该图含依赖环；等价地，`topo_order` 返回 `Err(Cycle)` 当且仅当 `detect_cycle` 返回 `Some`。

**Validates: Requirements 8.3, 13.2, 13.3**

### Property 14：动态依赖拓扑保持（dynamic-dependency topology preservation）

*对任意*由生成器产出的无环构建图与不引入环的动态依赖追加，并入后的图仍无环，且 `reschedule_with_dynamic` 重新产出的调度仍满足拓扑不变量（每目标在其全部依赖之后）。

**Validates: Requirements 8.1, 8.2, 8.4**

### Property 15：可复现性与溯源确定（reproducibility & provenance determinism）

*对任意*由生成器产出的（目标, 输入内容哈希集合, 动作 recipe），`record_provenance` 产出逐字段一致的溯源记录（相同输入与动作恒得相同输出哈希与相同记录）；且对任一输入哈希或动作指纹的变异，产出的溯源记录不同（差异可区分）。

**Validates: Requirements 9.1, 9.2, 9.3, 9.4**
