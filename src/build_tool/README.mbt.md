# build_tool · 可执行文档

> **方向六（R6）增量并行构建工具** — 规则解析 · 拓扑调度 · 环检测 · 三后端一致 · 文档即测试。
>
> 本文件既是 `build_tool` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/build_tool/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）**，tasks.md **任务 9.5**。

本文件作为 `build_tool` 包的黑盒测试运行，可直接调用本包公开 API
（`parse_rules` / `schedule` / `topo_order` / `detect_cycle` / `is_dirty` 等）而无需限定包名。
下面 4 段示例覆盖 **规则解析 → 构建图 → 拓扑调度（并行批次）→ 环检测** 的端到端流程，
并复用既有图资产 `@directed.topological_sort` 与 `@directed.tarjan_scc`。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明该段为一个独立条目。
>
> **关于类型构造**：黑盒 `.mbt.md` 对「表达式位置直接构造枚举变体」有限制，因此本文档
> 统一通过公开构造函数（`Target::new` / `BuildGraph::new`）创建数据，并以 `match` 解构
> `Result` / `Option` 结果。

---

## 规则文法（grammar）

`parse_rules` 接受最小可用规则文法（每行一条规则）：

```text
# 以 '#' 起始的行为注释，空行忽略
target : dep1 dep2 dep3
```

语义：`target` 依赖空格分隔的 `dep*`；对每个依赖生成一条边 `(dep, target)`
（表示「dep 必须在 target 之前」）。目标与依赖均登记为图节点（按首次出现去重）。

---

## 示例 1 · 规则解析 —— 文本规则 → 构建图

`parse_rules(src)` 把构建规则文本解析为以产物为节点、依赖为边的 `BuildGraph`
（满足 **R6.1**）。下例把顶层产物 `app` 及其两个目标文件解析为图：节点按首次出现
去重，依赖边方向为「依赖 → 产物」。

```mbt check
///|
test "README · parse_rules 解析规则为构建图" {
  let src = "# 顶层产物\napp: main.o util.o\nmain.o: common.h\nutil.o: common.h\n"
  match parse_rules(src) {
    Ok(g) => {
      // 节点：app、main.o、util.o、common.h —— common.h 仅登记一次（去重）
      @test.assert_eq(g.nodes.length(), 4)
      assert_true(g.nodes[0] == Target::new("app"))
      // 边：(main.o→app)、(util.o→app)、(common.h→main.o)、(common.h→util.o)
      @test.assert_eq(g.edges.length(), 4)
      let (dep0, tgt0) = g.edges[0]
      assert_true(dep0 == Target::new("main.o"))
      assert_true(tgt0 == Target::new("app"))
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}
```

---

## 示例 2 · 拓扑调度 —— 产出可并行的执行批次

`schedule(g, jobs)` 按拓扑「分层」产出并行批次：同一批次内的目标相互无依赖、可并行
执行，批次间严格满足「任一目标在其所有依赖之后」的拓扑不变量（满足 **R6.5 / R6.7**）。
下例中 `common.h` 先行，`main.o` 与 `util.o` 相互无依赖落入同一批次并行构建，最后构建
顶层产物 `app`。

```mbt check
///|
test "README · schedule 分层产出并行批次" {
  match
    parse_rules("app: main.o util.o\nmain.o: common.h\nutil.o: common.h\n") {
    Ok(g) => {
      // jobs=4：并行度足够，宽层不切分
      let batches = schedule(g, 4)
      // 三个批次：[common.h] → [main.o, util.o] → [app]
      @test.assert_eq(batches.length(), 3)
      // 第一批只有无依赖的 common.h
      @test.assert_eq(batches[0].length(), 1)
      assert_true(batches[0][0] == Target::new("common.h"))
      // 第二批 main.o 与 util.o 相互无依赖，可并行构建
      @test.assert_eq(batches[1].length(), 2)
      assert_true(batches[1][0] == Target::new("main.o"))
      assert_true(batches[1][1] == Target::new("util.o"))
      // 最后构建顶层产物 app
      @test.assert_eq(batches[2].length(), 1)
      assert_true(batches[2][0] == Target::new("app"))
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}
```

`jobs` 还可约束批内并行宽度：当某层目标数超过 `jobs` 时，该宽层会被切分为多个
批宽不超过 `jobs` 的批次。下例五个相互无依赖的目标在并行度上限 2 下切为 `2 + 2 + 1`。

```mbt check
///|
test "README · schedule 按 jobs 上限切分宽层" {
  let nodes = [
    Target::new("a"),
    Target::new("b"),
    Target::new("c"),
    Target::new("d"),
    Target::new("e"),
  ]
  // 五个相互无依赖目标，无边；并行度上限 2 → 2 + 2 + 1 三批
  let batches = schedule(BuildGraph::new(nodes, []), 2)
  @test.assert_eq(batches.length(), 3)
  @test.assert_eq(batches[0].length(), 2)
  @test.assert_eq(batches[1].length(), 2)
  @test.assert_eq(batches[2].length(), 1)
}
```

---

## 示例 3 · 拓扑序 —— 复用 @directed 给出线性执行顺序

`topo_order(g)` 复用既有图资产 `@directed.topological_sort`（Kahn 算法）计算合法执行
顺序，保证每个目标排在其全部依赖之后（满足 **R6.3**）。下例线性依赖 `a → b → c`
（即 `b` 依赖 `a`、`c` 依赖 `b`）给出唯一拓扑序 `[a, b, c]`。

```mbt check
///|
test "README · topo_order 复用 @directed 给出拓扑序" {
  // "b: a" 表示 b 依赖 a；"c: b" 表示 c 依赖 b
  match parse_rules("b: a\nc: b\n") {
    Ok(g) =>
      match topo_order(g) {
        Ok(order) => {
          // 依赖先于产物：a → b → c
          let names = order.map(fn(t) { t.name })
          assert_true(names == ["a", "b", "c"])
        }
        Err(_) => fail("无环图不应报告环")
      }
    Err(_) => fail("合法规则不应解析失败")
  }
}
```

---

## 示例 4 · 环检测 —— 报告构成环的目标序列

`detect_cycle(g)` 复用 `@directed.tarjan_scc` 识别强连通分量：存在依赖环时返回构成环的
目标序列并据此拒绝构建（满足 **R6.2**）；无环返回 `None`。`topo_order` 在有环时同样
返回含具体环节点序列的 `Cycle`。下例构造互相依赖的 `a ↔ b`。

```mbt check
///|
test "README · detect_cycle 报告依赖环并拒绝拓扑排序" {
  // "a: b" 与 "b: a" 互相依赖，构成环 a ↔ b
  match parse_rules("a: b\nb: a\n") {
    Ok(g) => {
      // 检出依赖环：返回构成环的两个目标
      match detect_cycle(g) {
        Some(cycle_nodes) => @test.assert_eq(cycle_nodes.length(), 2)
        None => fail("应检出 a↔b 依赖环")
      }
      // 有环图不应给出拓扑序，而是返回含环节点序列的 Cycle
      match topo_order(g) {
        Ok(_) => fail("有环图不应给出拓扑序")
        Err(cycle) => @test.assert_eq(cycle.nodes.length(), 2)
      }
    }
    Err(_) => fail("合法规则不应解析失败")
  }
  // 无环图：detect_cycle 返回 None
  let acyclic = BuildGraph::new([Target::new("solo")], [])
  assert_true(detect_cycle(acyclic) is None)
}
```

---

## 示例 5 · 完整规则文法 —— 变量 / recipe / 模式规则 / phony

`parse_rules_full(src)` 在 `@parser_combinator` 之上解析完整规则文法（旁路新增，
**不改**既有 `parse_rules` 最小文法语义）：变量定义与 `$(name)` 展开、缩进 recipe
原文、模式规则 `%` 词干回填、`.PHONY` 标记（满足 **R1**）。下例解析一段含变量、
recipe、模式规则与 phony 的规则集，并实例化模式规则。

```mbt check
///|
test "README · parse_rules_full 解析完整文法" {
  let src =
    #|CC = gcc
    #|.PHONY: clean
    #|app: main.o
    #|	$(CC) -o app main.o
    #|%.o: %.c
    #|	$(CC) -c $*.c
    #|
  match parse_rules_full(src) {
    Ok(rs) => {
      // 变量定义入表
      assert_true(rs.variables.get("CC") == Some("gcc"))
      // phony 标记
      assert_true(rs.is_phony("clean"))
      // recipe 中的 $(CC) 在解析期展开
      match rs.recipe_of("app") {
        Some(r) => assert_true(r.lines[0] == "gcc -o app main.o")
        None => fail("app 应有 recipe")
      }
      // 模式规则 %.o: %.c 按词干 stem 回填（foo.o → 依赖 foo.c）
      match rs.match_pattern("foo.o") {
        Some(rule) => {
          assert_true(rule.target == "foo.o")
          assert_true(rule.deps[0] == "foo.c")
          assert_true(rule.recipe.lines[0] == "gcc -c foo.c")
        }
        None => fail("应匹配模式 %.o")
      }
    }
    Err(_) => fail("合法规则不应解析失败")
  }
}
```

语法错误由旁路 `GrammarError`（携带行 / 列 / 偏移）承载，并可经 `to_legacy()`
投影回既有 `ParseError`，既满足列号诊断又不破坏既有契约（**R2.3**）。

---

## 示例 6 · 内容寻址增量缓存 —— 命中即跳过

缓存键由目标、输入内容哈希与动作指纹经**长度前缀单射编码**复合（满足 **R3**）：
相同输入产相同键、任一分量改变即产不同键。命中跳过重建，内容哈希变化（即便
时间戳未变）仍判键变化而重建（对标 Bazel / Ninja 的内容寻址优于纯时间戳）。

```mbt check
///|
test "README · 内容寻址缓存命中即跳过重建" {
  let recipe : Recipe = { lines: ["gcc -c x.c"] }
  let afp = action_fingerprint(recipe)
  let h_src = content_hash("int main() {}")
  let cache = ActionCache::new()
  // 首次：未命中 → 需重建
  assert_true(needs_rebuild_by_key(cache, "x.o", [h_src], afp))
  // 登记动作结果后：命中 → 跳过
  cache.record(cache_key("x.o", [h_src], afp), content_hash("<x.o>"))
  assert_false(needs_rebuild_by_key(cache, "x.o", [h_src], afp))
  // 输入内容变化 → 缓存键变化 → 再次需重建
  let h_src2 = content_hash("int main() { return 1; }")
  assert_true(needs_rebuild_by_key(cache, "x.o", [h_src2], afp))
}
```

`serialize_cache` / `deserialize_cache` 以键升序的确定性行式文本持久化 `BuildCache`，
满足往返一致（**R4**），使增量优势可跨构建会话保留。

---

## 示例 7 · 最小重建集 —— 单源变更只重建受影响目标

`minimal_rebuild_set(g, dirty)` 沿依赖边前向传播脏输入，得到**既充分又最小**的
重建集（满足 **R5/R6**）。下例对端到端 demo 工程仅改动一个源文件，重建集只含其
传递下游，相对全量目标数显著缩减。

```mbt check
///|
test "README · 最小重建集只含单源传递下游" {
  let g = demo_graph()
  // 仅 util_a.c 变化 → 下游 util_a.o → libutil.a → app
  let set = minimal_rebuild_set(g, [Target::new("util_a.c")])
  @test.assert_eq(set.length(), 4)
  // 相对 10 个全量目标显著缩减
  assert_true(set.length() < g.nodes.length())
}
```

---

## 示例 8 · 关键路径调度 —— 不限并行下的最小层数

`critical_path_length(g)` 在拓扑序上做最长路径 DP，等于不限并行度（`jobs <= 0`）
下完成构建所需的批次层数（满足 **R7.4**）：`critical_path_length(g) ==
len(schedule(g, 0))`。

```mbt check
///|
test "README · 关键路径长度等于不限并行批次层数" {
  let g = demo_graph()
  // 最长链：源 → *.o → 库 → app（4 个节点）
  @test.assert_eq(critical_path_length(g), 4)
  @test.assert_eq(critical_path_length(g), schedule(g, 0).length())
}
```

---

## 示例 9 · provenance 溯源 —— 可复现记录

`record_provenance` 产出含目标、输入哈希（规范升序）、动作指纹与输出哈希的溯源
记录（满足 **R9**）：相同输入与动作恒得相同记录（输入哈希乱序经规范化后仍一致），
任一分量变异记录可区分。

```mbt check
///|
test "README · 溯源记录可复现且差异可区分" {
  let recipe : Recipe = { lines: ["gcc -c x.c -o x.o"] }
  let p1 = record_provenance("x.o", ["h_src", "h_hdr"], recipe)
  // 输入哈希乱序 → 规范升序后记录一致
  let p2 = record_provenance("x.o", ["h_hdr", "h_src"], recipe)
  assert_true(p1 == p2)
  // 任一输入变化 → 记录不同
  assert_true(p1 != record_provenance("x.o", ["h_src2", "h_hdr"], recipe))
}
```

---

## 示例 10 · 端到端实战 —— 多模块工程依赖图

`demo_rules()` 是一份贯穿文档与基准的多模块 C / MoonBit 工程规则集（满足 **R10**）。
下例串联 `parse_rules` → `detect_cycle`（无环）→ `schedule`（拓扑分层）→
`minimal_rebuild_set`（增量）的端到端流程。

```mbt check
///|
test "README · 端到端 demo 解析-环检测-调度-增量" {
  match parse_rules(demo_rules()) {
    Ok(g) => {
      // 10 个目标：app / 两个库 / 三个 .o / 三个源 / 共享头
      @test.assert_eq(g.nodes.length(), 10)
      // 工程图无依赖环
      assert_true(detect_cycle(g) is None)
      // 调度为 4 层：源 → .o → 库 → app
      @test.assert_eq(schedule(g, 0).length(), 4)
      // 单源变更增量：仅 4 个目标重建
      @test.assert_eq(
        minimal_rebuild_set(g, [Target::new("core_a.c")]).length(),
        4,
      )
    }
    Err(_) => fail("demo 规则不应解析失败")
  }
}
```

---

## paper-to-code 可追溯与开源对标

| 算法 / 规范 | 来源 | 本库落点 |
|---|---|---|
| rebuilder / scheduler 两维分解 | Mokhov, Mitchell, Peyton Jones《Build Systems à la Carte》 | rebuilder ↔ `rebuild.mbt`（脏传播 / 最小重建集 / 缓存命中）；scheduler ↔ `scheduler.mbt` + 既有 `schedule` |
| 拓扑序（Kahn 逐层剥离入度 0） | Kahn 1962 | 既有 `topo_order` / `schedule` 复用 `@directed.topological_sort` |
| 强连通分量（环检测） | Tarjan 1972 | 既有 `detect_cycle` 复用 `@directed.tarjan_scc` |
| DAG 最长路径（关键路径） | 拓扑序动态规划 | `critical_path_length`（topo 序 `longest[v]` DP） |
| 内容寻址缓存 | Bazel / Nix / Ninja | `content_hash` / `cache_key`（长度前缀单射键）/ `ActionCache` |
| 可复现构建（输入 + 动作 → 输出确定） | Bazel / Nix | `derive_output_hash` / `record_provenance` |

与主流构建系统的取舍对比（内容经改写以符合许可约定）：本库与 Bazel / Buck2 同侧
——以**内容寻址缓存 + 确定性调度 + 可复现溯源**换取最强增量正确性与可审计性，
而非 GNU Make 的「时间戳 + 递归」简易模型；同时保留 Make 风格的可读规则文法（变量 /
模式规则 / phony），在表达力与形式化可验证性间取平衡。Ninja 以显式 DAG + 关键路径
并行为主、规则文法极简；Bazel / Buck2 以 Starlark 描述、内容寻址 + 远程执行。

参考：
[Build Systems à la Carte](https://www.microsoft.com/en-us/research/publication/build-systems-la-carte/)
· [Ninja manual](https://ninja-build.org/manual.html)
· [Bazel](https://bazel.build/)。

## 实现边界声明（R12.4，显式而非隐式留白）

本方向是构建系统的**图与缓存模型层**，停留在「依赖图、调度、增量缓存、溯源记录」
抽象层：

- **不**执行真实文件系统读写：输入指纹（mtime + 内容哈希）由调用方经
  `BuildCache::observe` 注入，本库不扫描磁盘。
- **不**派生构建进程、**不**调用编译器：recipe 以不透明字符串及其指纹建模；
  「输出」以 `derive_output_hash` 的确定性函数建模，不真正执行命令。
- **include 不做跨文件 FS 解析**：`parse_rules_full_with_includes` 由调用方注入
  include 名 → 源文本的 `resolve` 函数（单进程模型）。
- **可复现性是模型层假设**：建模为「输出哈希 = f(输入哈希, 动作指纹)」，对应
  Bazel / Nix 的可复现内核，但不验证真实工具链的可复现性。

该边界使核心算法可被属性测试穷尽校验，且 `wasm-gc` / `js` / `native` 三后端逐位
一致。

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/build_tool/README.mbt.md

# 三后端一致性（R11.1 / R6.8）：同一文档套件在三后端均须通过
moon test src/build_tool/README.mbt.md --target wasm-gc
moon test src/build_tool/README.mbt.md --target js
moon test src/build_tool/README.mbt.md --target native
```

预期看到：

```
Total tests: 11, passed: 11, failed: 0.
```

（示例 1~10 的 11 段可执行测试全部通过。）一旦修改实现使其输出与本文档的
`assert_*` 断言不符，`moon test` 会立即报错并以最小化差异提示同步更新文档——这正是
MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
