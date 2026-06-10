# Tarjan SCC · 强连通分量

## 背景

Robert Tarjan 在 1972 年论文 *Depth-First Search and Linear Graph Algorithms*
中提出，可以**在一次 DFS 过程中**直接找到有向图的所有**强连通分量**
（Strongly Connected Components, SCC）——互相可达的极大节点子集。
与 Kosaraju 的"两次 DFS"方案相比，Tarjan 一次扫描、节省一半栈开销，是
现代编译器、程序分析、图数据库、形式验证里最常用的 SCC 方案。

## 核心思想

**DFS + 三个辅助数组**：

- `index[v]`：节点 `v` 被 DFS 访问的时间戳（0, 1, 2, ...）；
- `lowlink[v]`：从 `v` 出发经过 DFS 子树能回到的"最小 index"——SCC 的
  "根"正是那些 `lowlink[v] == index[v]` 的节点；
- `on_stack[v]`：布尔，表示 `v` 当前仍在"尚未归属任何 SCC"的栈里。

遍历时遇到后向边（指向 `on_stack` 中的节点）就更新 `lowlink` 为那个更早
的 `index`；遇到已完成的节点直接忽略（它属于之前已归属的 SCC，不会回来）。

## 算法骨架

```
index_counter ← 0
stack ← []
sccs ← []
for v in nodes:
  if v.index 未定义: strongconnect(v)

fn strongconnect(v):
  v.index ← index_counter
  v.lowlink ← index_counter
  index_counter += 1
  stack.push(v); v.on_stack ← true
  for w in successors(v):
    if w.index 未定义:
      strongconnect(w)                       // 递归进入树边
      v.lowlink ← min(v.lowlink, w.lowlink)  // 子树回跳
    elif w.on_stack:
      v.lowlink ← min(v.lowlink, w.index)    // 后向/横向边
  if v.lowlink == v.index:                   // v 是 SCC 根
    comp ← []
    repeat:
      w ← stack.pop(); w.on_stack ← false
      comp.push(w)
    until w == v
    sccs.push(comp)
```

**本库实现的工程化加固**：递归改为**显式栈**，避免 MoonBit 对深递归的
限制；栈元素为 `(node, iterator-position)`，用 `while` 循环模拟每层的"处理
当前子边、回溯、更新 lowlink"。

## 时间复杂度

- **时间** O(V + E)：每节点访问一次，每边扫描一次；
- **空间** O(V)：三个辅助数组与栈。

这是渐进意义上的**最优**——任何 SCC 算法都必须读到每条边至少一次。

## 典型场景

1. **程序控制流分析**：编译器把函数的 CFG（控制流图）做 SCC 划分，
   SCC 里的节点必属同一个循环；非 SCC 节点组成 DAG 可轻松做数据流分析；
2. **死代码消除与编译优化**：只对同一 SCC 内做环路优化，跨 SCC 采取
   不同策略；
3. **图数据库 / 知识图谱**：Wikipedia 页面互链网络的 SCC 是"话题簇"；
4. **符号执行 / Model Checking**：验证状态机里的"可达的强连通状态集"，
   支持 liveness 性质证明；
5. **2-SAT 问题**：把蕴含图的 SCC 取并后倒序得到真赋值。

## MoonBit API 示例

```moonbit
// 0→1→2→0 构成一个 SCC；3→4→3 构成另一 SCC；5 独立
let nodes = [0, 1, 2, 3, 4, 5]
let adj : Array[Array[Int]] = [[1], [2], [0], [4], [3], []]
let sccs = @directed.tarjan_scc(nodes, fn(n) { adj[n] })
// sccs.length() == 3
```

**whitebox 用例**：本库覆盖了"单节点自环"场景——节点 0 + 自环 `0 → 0`
应视作**一个 SCC**（因为 0 可达自己），而非 singleton。这正好触发
`on_stack.get(w).or(false) == true` 的分支（源文件 `tarjan_scc.mbt`）。

## 参考文献

- Tarjan, R. E. (1972). "Depth-first search and linear graph algorithms."
  *SIAM Journal on Computing*, 1(2), 146–160.
- Kosaraju, S. R. (1978). unpublished lecture notes.
- CLRS 22.5。
