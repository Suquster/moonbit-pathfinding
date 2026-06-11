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
Total tests: 7, passed: 7, failed: 0.
```

（示例 1~5 共 7 段可执行测试全部通过。）一旦修改寄存器分配 / SSA / 指令选择实现使其
输出与本文档的 `inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test`
会立即报错并以最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
