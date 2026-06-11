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
      assert_eq(g.nodes.length(), 4)
      assert_true(g.nodes[0] == Target::new("app"))
      // 边：(main.o→app)、(util.o→app)、(common.h→main.o)、(common.h→util.o)
      assert_eq(g.edges.length(), 4)
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
      assert_eq(batches.length(), 3)
      // 第一批只有无依赖的 common.h
      assert_eq(batches[0].length(), 1)
      assert_true(batches[0][0] == Target::new("common.h"))
      // 第二批 main.o 与 util.o 相互无依赖，可并行构建
      assert_eq(batches[1].length(), 2)
      assert_true(batches[1][0] == Target::new("main.o"))
      assert_true(batches[1][1] == Target::new("util.o"))
      // 最后构建顶层产物 app
      assert_eq(batches[2].length(), 1)
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
  assert_eq(batches.length(), 3)
  assert_eq(batches[0].length(), 2)
  assert_eq(batches[1].length(), 2)
  assert_eq(batches[2].length(), 1)
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
        Some(cycle_nodes) => assert_eq(cycle_nodes.length(), 2)
        None => fail("应检出 a↔b 依赖环")
      }
      // 有环图不应给出拓扑序，而是返回含环节点序列的 Cycle
      match topo_order(g) {
        Ok(_) => fail("有环图不应给出拓扑序")
        Err(cycle) => assert_eq(cycle.nodes.length(), 2)
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
Total tests: 4, passed: 4, failed: 0.
```

（示例 1~4 的 4 段可执行测试全部通过。）一旦修改实现使其输出与本文档的
`assert_*` 断言不符，`moon test` 会立即报错并以最小化差异提示同步更新文档——这正是
MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
