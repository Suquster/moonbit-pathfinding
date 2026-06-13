# codegen_infra · 可执行文档

> **方向三（R3）代码生成基础设施** — 寄存器分配 · SSA 构造 · 指令选择 · 三后端一致 · 文档即测试。
>
> 本文件既是 `codegen_infra` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/codegen_infra/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）**，tasks.md **任务 11.5**。

本文件作为 `codegen_infra` 包的黑盒测试运行，可直接调用本包公开 API
（`allocate_coloring` / `allocate_linear_scan` / `build_ssa` / `run_passes` / `select` 等）
而无需限定包名。下面 5 段示例覆盖 **干涉图着色分配 → 线性扫描 → SSA 构造（φ 插入 /
版本化）→ pass 流水线 → 指令选择 DSL** 的端到端流程，其中干涉图着色复用既有
`@directed` 图资产（见 `interference_components`）。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明该段为一个独立条目。
>
> **关于类型构造**：黑盒 `.mbt.md` 对「表达式位置直接构造枚举变体」有限制，因此本文档
> 统一用 `Type::{...}` 结构体字面量构造数据（`Var` / `InterferenceGraph` / `LiveInterval` /
> `BasicBlock` / `IselRule`），用限定形式 `Type::Variant` 构造枚举（`IrNode` / `Pass`），
> 并以 `match` 解构 `Location`（`Reg` / `Spill`）结果。

---

## 数据模型速览

* `Var{ id }` —— 变量（虚拟寄存器）标识，作为干涉图节点与分配结果的键。
* `Location` —— 物理存储位置：`Reg(Int)`（物理寄存器编号）或 `Spill(Int)`（溢出栈槽）。
* `InterferenceGraph{ nodes, edges }` —— 干涉图：`edges` 中的变量对「同时活跃」而互相干涉。
* `allocate_coloring(g, k) -> Map[Var, Location]` —— 图着色分配：相互干涉的变量不共享寄存器，
  寄存器不足则溢出（**R3.1 / R3.3**）。
* `allocate_linear_scan(intervals, k) -> Map[Var, Location]` —— 线性扫描分配（**R3.2**）。
* `build_ssa(blocks) -> SsaProgram` —— 构造 SSA：版本化定义 + 汇合点 φ 插入（**R3.4 / R3.5**）。
* `run_passes(p, passes) -> SsaProgram` —— 按声明顺序执行优化 pass 并保持 SSA 不变量（**R3.6**）。
* `select(rules, ir) -> Array[TargetInstr]` —— 声明式指令选择 DSL（**R3.7**）。

---

## 示例 1 · 干涉图 k 着色分配 —— 相邻变量不共享寄存器

`allocate_coloring(g, k)` 复用既有图资产把干涉图分解为连通分量后做贪心 k 着色：
为每个变量选取未被「已着色邻居」占用的最小寄存器，寄存器耗尽则溢出到栈槽
（满足 **R3.1 / R3.3**）。下例构造三角干涉图 `K3`（三个变量两两干涉）：在 `k=3`
时三者各得一个互不相同的寄存器、无溢出。

```mbt check
///|
test "README · allocate_coloring 在 k=3 时为 K3 分配互不相同的寄存器" {
  // 三个两两干涉的变量构成三角图 K3
  let g = InterferenceGraph::{
    nodes: [Var::{ id: 0 }, Var::{ id: 1 }, Var::{ id: 2 }],
    edges: [
      (Var::{ id: 0 }, Var::{ id: 1 }),
      (Var::{ id: 1 }, Var::{ id: 2 }),
      (Var::{ id: 0 }, Var::{ id: 2 }),
    ],
  }
  let alloc = allocate_coloring(g, 3)
  assert_eq(alloc.length(), 3)
  // 收集每个变量分到的寄存器编号；K3 无溢出，三者编号两两不同
  let regs = []
  for v in g.nodes {
    match alloc.get(v) {
      Some(Reg(r)) => regs.push(r)
      Some(Spill(_)) => fail("k=3 足以为 K3 着色，不应溢出")
      None => fail("每个变量都应获得分配")
    }
  }
  regs.sort()
  inspect(regs[0], content="0")
  inspect(regs[1], content="1")
  inspect(regs[2], content="2")
}
```

寄存器不足时则发生**溢出**：`k=2` 无法为三角图三着色，至少一个变量落到 `Spill`，
但干涉不变量仍然成立——任意相邻变量绝不共享同一寄存器。

```mbt check
///|
test "README · allocate_coloring 在 k=2 时溢出且保持干涉不变量" {
  let g = InterferenceGraph::{
    nodes: [Var::{ id: 0 }, Var::{ id: 1 }, Var::{ id: 2 }],
    edges: [
      (Var::{ id: 0 }, Var::{ id: 1 }),
      (Var::{ id: 1 }, Var::{ id: 2 }),
      (Var::{ id: 0 }, Var::{ id: 2 }),
    ],
  }
  let alloc = allocate_coloring(g, 2)
  // 统计溢出数量：k=2 时 K3 至少溢出一个变量
  let mut spills = 0
  for v in g.nodes {
    match alloc.get(v) {
      Some(Spill(_)) => spills = spills + 1
      _ => ()
    }
  }
  assert_true(spills >= 1)
  // 干涉不变量（R3.3）：相邻两端若都着色为寄存器，则编号必不相同
  for e in g.edges {
    let (a, b) = e
    match (alloc.get(a), alloc.get(b)) {
      (Some(Reg(x)), Some(Reg(y))) => assert_true(x != y)
      _ => ()
    }
  }
}
```

---

## 示例 2 · 线性扫描分配 —— 非重叠活跃区间复用寄存器

`allocate_linear_scan(intervals, k)` 按活跃区间起点升序处理，先回收已过期区间占用的
寄存器，再为当前区间分配空闲寄存器（满足 **R3.2**）。下例三个区间中 `A[0,2]` 与
`B[1,3]` 重叠各占一个寄存器，而 `C[4,6]` 在 `A` 过期后复用其寄存器，`k=2` 即足够、无溢出。

```mbt check
///|
test "README · allocate_linear_scan 非重叠区间复用寄存器" {
  let intervals = [
    LiveInterval::{ variable: Var::{ id: 0 }, start: 0, end: 2 },
    LiveInterval::{ variable: Var::{ id: 1 }, start: 1, end: 3 },
    LiveInterval::{ variable: Var::{ id: 2 }, start: 4, end: 6 },
  ]
  let alloc = allocate_linear_scan(intervals, 2)
  // A 与 B 重叠，占用两个不同寄存器；C 在 A 过期后复用寄存器 0
  match alloc.get(Var::{ id: 0 }) {
    Some(Reg(r)) => inspect(r, content="0")
    _ => fail("A 应分到寄存器")
  }
  match alloc.get(Var::{ id: 1 }) {
    Some(Reg(r)) => inspect(r, content="1")
    _ => fail("B 应分到寄存器")
  }
  match alloc.get(Var::{ id: 2 }) {
    Some(Reg(r)) => inspect(r, content="0")
    _ => fail("C 应复用 A 释放的寄存器")
  }
}
```

---

## 示例 3 · SSA 构造 —— φ 插入与版本化

`build_ssa(blocks)` 把基本块序列转换为 SSA 形式：块内 `name = rhs` 定义被重写为带
版本号的 `name#ver`，并在拥有 ≥2 个前驱的汇合块为多处定义的变量插入 φ 函数
（满足 **R3.4 / R3.5**）。下例为经典菱形控制流——`x` 在 `then` / `else` 两分支各定义
一次，在汇合块 `join` 处插入一个有两个实参的 φ；左值定义被版本化为 `x#0`。

```mbt check
///|
test "README · build_ssa 在菱形汇合点插入 φ 并版本化定义" {
  let p = build_ssa([
    BasicBlock::{ label: "entry", instrs: [], succs: ["then", "else"] },
    BasicBlock::{ label: "then", instrs: ["x = 1"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ])
  // 汇合块有两个前驱（then / else），为 x 插入一个 φ
  inspect(p.phis.length(), content="1")
  // φ 实参数等于汇合块前驱数
  inspect(p.phis[0].args.length(), content="2")
  // then 块定义左值被版本化为 x#0
  inspect(p.blocks[1].instrs[0], content="x#0 = 1")
}
```

直线代码无汇合点，故不插入 φ；右值使用被重写为引用最近定义的版本（`y#1 = x#0 + 2`）。

```mbt check
///|
test "README · build_ssa 直线代码不插入 φ 且版本化右值使用" {
  let p = build_ssa([
    BasicBlock::{ label: "b0", instrs: ["x = 1", "y = x + 2"], succs: [] },
  ])
  inspect(p.phis.length(), content="0")
  inspect(p.blocks[0].instrs[0], content="x#0 = 1")
  // y 的右值使用 x 被重写为引用其最近版本 x#0
  inspect(p.blocks[0].instrs[1], content="y#1 = x#0 + 2")
}
```

---

## 示例 4 · pass 流水线 —— 按声明顺序优化并保持 SSA

`run_passes(p, passes)` 按声明顺序依次施加各优化 pass，且每个 pass 后保持 SSA 单赋值
不变量（满足 **R3.6**）。下例先 `build_ssa` 再依次执行常量折叠（`ConstFold`）与死代码
消除（`DeadCodeElim`）：`x = 1 + 2` 折叠为 `x#0 = 3`，而从未被使用的定义 `z = 9` 被删除。

```mbt check
///|
test "README · run_passes 常量折叠后再死代码消除" {
  let base = build_ssa([
    BasicBlock::{
      label: "b0",
      instrs: ["x = 1 + 2", "z = 9", "ret x"],
      succs: [],
    },
  ])
  let out = run_passes(base, [Pass::ConstFold, Pass::DeadCodeElim])
  // 常量折叠：x = 1 + 2 → x#0 = 3
  inspect(out.blocks[0].instrs[0], content="x#0 = 3")
  // 死代码消除：未被任何使用引用的 z 定义被删除，仅剩 x 定义与 ret
  inspect(out.blocks[0].instrs.length(), content="2")
  inspect(out.blocks[0].instrs[1], content="ret x#0")
}
```

---

## 示例 5 · 指令选择 DSL —— 声明式规则覆盖 IR 树

`select(rules, ir)` 以声明式规则（`IselRule{ pattern, template }`）后序遍历 IR 树，
为每个节点按模式查表选择目标操作码（满足 **R3.7**）。模式 `"Const"` / `"VarRef"` /
`"BinOp"` 分别匹配常量、变量引用与二元运算，`"BinOp:<op>"` 可特化具体运算符并优先于
通用 `"BinOp"`。下例把 `(3 * 4)` 选择为两条 `li` 装载与一条 `mul` 乘法指令。

```mbt check
///|
test "README · select 以声明式规则覆盖二元运算树" {
  let rules = [
    IselRule::{ pattern: "Const", template: "li" },
    IselRule::{ pattern: "BinOp:*", template: "mul" },
    IselRule::{ pattern: "BinOp", template: "add" },
  ]
  // IR 树：3 * 4
  let ir = IrNode::BinOp("*", IrNode::Const(3), IrNode::Const(4))
  let instrs = select(rules, ir)
  // 后序产出：li t0, 3 ; li t1, 4 ; mul t2, t0, t1
  inspect(instrs.length(), content="3")
  inspect(instrs[0].op, content="li")
  inspect(instrs[1].op, content="li")
  // 运算符特化 BinOp:* 优先于通用 BinOp，选中 mul
  inspect(instrs[2].op, content="mul")
  // mul 的操作数为目标寄存器与两个子树结果寄存器
  inspect(instrs[2].operands.length(), content="3")
  inspect(instrs[2].operands[0], content="t2")
  inspect(instrs[2].operands[1], content="t0")
  inspect(instrs[2].operands[2], content="t1")
}
```

---

## 示例 6 · 活跃性分析 —— 干涉图来自真实活跃性

`analyze_liveness(blocks)` 以后向数据流不动点计算各块 live-in / live-out；
`build_interference_from_liveness` 据此在「同一程序点同时活跃」的变量对间建边
（满足 **R4**，paper-to-code：经典后向数据流 / Appel）。下例中 `a` 与 `b` 在
`c = a + b` 处同时活跃，故二者干涉。

```mbt check
///|
test "README · analyze_liveness 驱动干涉图构造" {
  let blocks = [
    BasicBlock::{
      label: "b0",
      instrs: ["a = 1", "b = 2", "c = a + b", "ret c"],
      succs: [],
    },
  ]
  let live = analyze_liveness(blocks)
  let g = build_interference_from_liveness(blocks, live)
  inspect(g.nodes.length(), content="3")
  // a 与 b 同时活跃 → 恰一条干涉边
  inspect(g.edges.length(), content="1")
}
```

---

## 示例 7 · 支配树与支配边界（Lengauer-Tarjan / Cytron）

`build_dom_tree(blocks, entry~)` 以 Lengauer-Tarjan（1979）计算直接支配者；
`dominance_frontier` 以 Cytron et al.（1991）计算支配边界（满足 **R5**）。菱形 CFG
中 `then` / `else` / `join` 的直接支配者均为 `entry`，且 `join` 属于 `then` 的支配边界。

```mbt check
///|
test "README · build_dom_tree 与 dominance_frontier" {
  let blocks = [
    BasicBlock::{ label: "entry", instrs: ["cbr p then else"], succs: ["then", "else"] },
    BasicBlock::{ label: "then", instrs: ["x = 1", "br join"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2", "br join"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ]
  let dom = build_dom_tree(blocks, entry="entry")
  inspect(dom.reachable.length(), content="4")
  inspect(dom.dominates("entry", "join"), content="true")
  inspect(dom.dominates("then", "join"), content="false")
  let df = dominance_frontier(blocks, dom)
  // join 属于 then 的支配边界
  match df.get("then") {
    Some(frontier) => assert_true(frontier.contains("join"))
    None => fail("then 应有支配边界")
  }
}
```

---

## 示例 8 · 最小 SSA 构造（Cytron 支配边界 φ 放置）

`build_ssa_minimal(blocks, entry~)` 仅在变量定义的迭代支配边界放置 φ，并沿支配树
前序重命名（满足 **R6**）；在「直线 / 简单菱形」等最小文法上与冻结的 `build_ssa`
逐字段一致（向后兼容）。

```mbt check
///|
test "README · build_ssa_minimal 菱形最小 φ 放置" {
  let diamond = [
    BasicBlock::{ label: "entry", instrs: ["cbr p then else"], succs: ["then", "else"] },
    BasicBlock::{ label: "then", instrs: ["x = 1", "br join"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2", "br join"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ]
  let ssa = build_ssa_minimal(diamond, entry="entry")
  inspect(ssa.phis.length(), content="1")
  inspect(ssa.phis[0].args.length(), content="2")
  inspect(ssa.blocks[1].instrs[0], content="x#0 = 1")
}
```

---

## 示例 9 · SSA 析构（out-of-SSA）—— φ 消除且语义等价

`destruct_ssa(p)` 将每个 φ 消除为前驱边上的复制并破环序列化，产出不含 φ 的等价程序
（满足 **R7**，paper-to-code：Sreedhar / Boissinot）。以参考解释器 `evaluate` 为
oracle 验证：沿同一路径，析构前后输出一致。

```mbt check
///|
test "README · destruct_ssa 消除 φ 且语义等价" {
  let diamond = [
    BasicBlock::{ label: "entry", instrs: ["cbr p then else"], succs: ["then", "else"] },
    BasicBlock::{ label: "then", instrs: ["x = 1", "br join"], succs: ["join"] },
    BasicBlock::{ label: "else", instrs: ["x = 2", "br join"], succs: ["join"] },
    BasicBlock::{ label: "join", instrs: ["ret x"], succs: [] },
  ]
  let ssa = build_ssa_minimal(diamond, entry="entry")
  let d = destruct_ssa(ssa)
  inspect(d.phis.length(), content="0")
  // 沿 then 来路：析构前后输出一致（均为 1）
  let before = evaluate(ssa, Map([]), ["entry", "then", "join"]).output
  let after = evaluate(d, Map([]), ["entry", "then", "join"]).output
  assert_eq(before, after)
  inspect(after, content="[1]")
}
```

---

## 示例 10 · 数据流优化 —— SCCP 与 GVN（保持语义）

`sccp(p)`（Wegman-Zadeck 稀疏条件常量传播）折叠常量并替换常量变量的使用；
`gvn(p)`（全局值编号 + 强化 DCE / 复制传播）合并计算等价表达式（满足 **R8 / R9**）。

```mbt check
///|
test "README · sccp 折叠常量并替换使用" {
  let p = SsaProgram::{
    blocks: [
      BasicBlock::{
        label: "b0",
        instrs: ["x#0 = 5", "y#1 = x#0 + 1", "ret y#1"],
        succs: [],
      },
    ],
    phis: [],
  }
  let out = sccp(p)
  // x#0 = 5 常量 → y#1 = 5 + 1 折叠为 6 → ret 替换为字面量
  inspect(out.blocks[0].instrs[1], content="y#1 = 6")
  inspect(out.blocks[0].instrs[2], content="ret 6")
}
```

```mbt check
///|
test "README · gvn 合并计算等价的表达式" {
  let p = SsaProgram::{
    blocks: [
      BasicBlock::{
        label: "b0",
        instrs: [
          "a#0 = 5", "b#1 = 6", "x#2 = a#0 + b#1", "y#3 = a#0 + b#1", "ret y#3",
        ],
        succs: [],
      },
    ],
    phis: [],
  }
  let out = gvn(p)
  // y#3 与 x#2 计算等价 → y#3 删除，ret 引用替换为 x#2
  inspect(out.blocks[0].instrs.length(), content="4")
  inspect(out.blocks[0].instrs[3], content="ret x#2")
}
```

---

## 示例 11 · Chaitin-Briggs 乐观着色与线性扫描一致性

`allocate_coloring_briggs(g, k)` 实现 simplify / potential-spill / select 三阶段栈式
乐观着色（Chaitin 1982 / Briggs 1994，满足 **R1**）。在最大重叠度不超过 k 的区间集上，
图着色与线性扫描在「是否需要溢出」结论上一致（满足 **R3.5**）。

```mbt check
///|
test "README · allocate_coloring_briggs K3 在 k=3 无溢出" {
  let g = InterferenceGraph::{
    nodes: [Var::{ id: 0 }, Var::{ id: 1 }, Var::{ id: 2 }],
    edges: [
      (Var::{ id: 0 }, Var::{ id: 1 }),
      (Var::{ id: 1 }, Var::{ id: 2 }),
      (Var::{ id: 0 }, Var::{ id: 2 }),
    ],
  }
  let alloc = allocate_coloring_briggs(g, 3)
  inspect(allocation_has_spill(alloc), content="false")
  // 干涉不变量：相邻两端寄存器编号不同
  for e in g.edges {
    let (a, b) = e
    match (alloc.get(a), alloc.get(b)) {
      (Some(Reg(x)), Some(Reg(y))) => assert_true(x != y)
      _ => ()
    }
  }
}
```

```mbt check
///|
test "README · 线性扫描与图着色无溢出结论一致" {
  // 两个重叠区间（团大小 2），k=2 足够
  let intervals = [
    LiveInterval::{ variable: Var::{ id: 0 }, start: 0, end: 1 },
    LiveInterval::{ variable: Var::{ id: 1 }, start: 0, end: 1 },
  ]
  let g = interference_from_intervals(intervals)
  let by_coloring = allocate_coloring_briggs(g, 2)
  let by_linear = allocate_linear_scan(intervals, 2)
  // 两法均判无需溢出
  inspect(allocation_has_spill(by_coloring), content="false")
  inspect(allocation_has_spill(by_linear), content="false")
}
```

---

## 示例 12 · BURS 指令选择与端到端流水线

`select_burs(rules, ir)` 以自底向上动态规划求代价最优 tiling（满足 **R11**，
paper-to-code：BURS / Appel）；`tiling_cost` 给出最优总代价。`demo_pipeline()` 串起
活跃性 → 最小 SSA → SCCP/GVN/DCE → 图着色 / 线性扫描 → BURS 全链路（满足 **R12**）。

```mbt check
///|
test "README · select_burs 代价最优 tiling" {
  let rules = [
    CostRule::{ pattern: "Const", template: "li", cost: 1 },
    CostRule::{ pattern: "BinOp:*", template: "mul", cost: 2 },
    CostRule::{ pattern: "BinOp", template: "op", cost: 5 },
  ]
  let ir = IrNode::BinOp("*", IrNode::Const(3), IrNode::Const(4))
  let instrs = select_burs(rules, ir)
  // 特化 mul 优先且代价最优；最优 tiling 总代价 = 1 + 1 + 2 = 4
  inspect(instrs[2].op, content="mul")
  inspect(tiling_cost(rules, ir), content="4")
}
```

```mbt check
///|
test "README · demo_pipeline 端到端各阶段产物" {
  let stages = demo_pipeline()
  // 仅在支配边界放 φ：恰一个 φ
  inspect(stages.ssa.phis.length(), content="1")
  // k 充足：图着色无溢出
  inspect(allocation_has_spill(stages.coloring), content="false")
  // (n + 1) * 2 共 5 个 IR 节点 → 5 条目标指令
  inspect(stages.instrs.length(), content="5")
}
```

---

## paper-to-code 可追溯（R14.1 / 14.2）

| 算法 | 论文 / 规范 | 本库落点 |
|---|---|---|
| 图着色寄存器分配 | Chaitin 1982；Briggs 1994 乐观着色 | `allocate_coloring_briggs`（simplify / potential-spill / select） |
| 线性扫描分配 | Poletto-Sarnak 1999 | `allocate_linear_scan`（既有，冻结） |
| 寄存器合并 | George-Appel 1996；Briggs 保守判据 | `can_coalesce_george` / `can_coalesce_briggs` / `coalesce` |
| 支配树 | Lengauer-Tarjan 1979 | `build_dom_tree` |
| 支配边界 + 最小 SSA | Cytron et al. 1991 | `dominance_frontier` + `build_ssa_minimal` |
| SSA 析构 | Sreedhar et al. / Boissinot 并行复制破环 | `destruct_ssa` + `sequentialize_parallel_copy` |
| 稀疏条件常量传播 | Wegman-Zadeck 1991 | `sccp` |
| 全局值编号 | 值编号 / Appel《Modern Compiler Implementation》 | `gvn` |
| 活跃性分析 | 经典后向数据流；Appel | `analyze_liveness` |
| 指令选择 | BURS / 最大吞噬；Appel | `select_burs` / `max_munch` |

---

## 与主流编译器后端对标（R14.3）

| 维度 | 本库（Codegen_Infra） | LLVM | GCC | Cranelift | regalloc2 |
|---|---|---|---|---|---|
| 寄存器分配 | 图着色（Chaitin-Briggs）+ 线性扫描并存 | 贪心 + PBQP 可选 | 图着色（IRA） | 偏好引导 + 线性扫描风格 | SSA-based 回填 + 移动优化 |
| 合并 | George / Briggs 保守 | 复制合并 + rematerialization | 合并 + 重materialize | 偏好 / 约束驱动 | 移动消除 |
| SSA 构造 | Cytron 支配边界最小 φ | mem2reg + 支配边界 | GIMPLE→SSA | CLIF 即 SSA | 输入即 SSA |
| 指令选择 | BURS 代价最优 / 最大吞噬（模型层） | SelectionDAG / GlobalISel | RTL 模式 | ISLE 模式 | 不涉及 isel |
| 输出层级 | **IR / 算法模型层，不产机器码** | 真实机器码 | 真实机器码 | 真实机器码 | 仅分配结果 |

---

## 实现边界声明（R14.4 / 14.5）

Codegen_Infra 是编译器后端的**算法与中间表示模型层**，停留在「控制流图、活跃性、
支配关系、SSA、数据流优化、寄存器分配、指令选择」这一抽象层：

- **不**生成真实目标机器码、**不**汇编或链接、**不**绑定任何具体指令集架构（ISA）；
- IR 为简化教学 / 研究模型（块内为空格分隔记号串、`IrNode` 为 `Const`/`VarRef`/`BinOp` 树）；
- 目标指令以不透明 `TargetInstr{ op, operands }` 建模，`op` 不解释为真实助记符；
- 寄存器为抽象编号，不做 rematerialization。

该边界是刻意取舍：以放弃真实机器码生成换取核心算法可被属性测试穷尽校验、三后端
逐位一致与 paper-to-code 透明可追溯。凡与所对标后端的语义差异均在此显式声明，而非
隐式留白。

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/codegen_infra/README.mbt.md

# 三后端一致性（R11.1 / R3.8）：同一文档套件在三后端均须通过
moon test src/codegen_infra/README.mbt.md --target wasm-gc
moon test src/codegen_infra/README.mbt.md --target js
moon test src/codegen_infra/README.mbt.md --target native
```

预期看到：

```
Total tests: 17, passed: 17, failed: 0.
```

（示例 1~12 共 17 段可执行测试全部通过。）一旦修改寄存器分配 / SSA / 指令选择实现使其
输出与本文档的 `inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test`
会立即报错并以最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
