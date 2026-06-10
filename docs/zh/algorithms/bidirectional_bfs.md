# Bidirectional BFS · 双向广度优先搜索

## 背景

单向 BFS 在"源远目标更远"的大规模图中代价随**分支因子 b** 与**路径深度 d**
呈 `O(b^d)` 膨胀。Ira Pohl 在 1971 年的博士论文中提出**双向 BFS**：
从源与目标**同时对向扩展**，两侧前沿相遇时即构造路径，把搜索空间从
`O(b^d)` 压到 `O(b^(d/2))` 级别——在 `b = 10, d = 10` 时是**五个数量级**
的差距。

## 核心思想

**同时扩展两条前沿**，始终挑**较小前沿**扩展以避免任一方向爆炸：

1. 维护 `fwd_queue`（从 `start` 出发用 `successors`）与 `bwd_queue`
   （从 `goal` 出发用 `predecessors`）；
2. 每轮检查两侧剩余队列长度，**扩展较小那侧**；
3. 新访问节点若已出现在**对侧** `visited` 中，即为**会合点** `m`，此时
   路径 = `start → ... → m`（沿 `fwd_parent`）+ `m → ... → goal`
   （沿 `bwd_parent` 反向）。

## 算法步骤（对应 `src/directed/bidirectional_bfs.mbt` 真实实现）

```
fwd_queue ← [start]; fwd_visited ← {start}; fwd_parent ← {}
bwd_queue ← [goal];  bwd_visited ← {goal};  bwd_parent ← {}
while 两侧队列均非空:
  if fwd_size <= bwd_size:
    u ← fwd_queue.dequeue()
    for v in successors(u):
      若 v 未访问:
        fwd_visited.add(v); fwd_parent[v] ← u
        if v ∈ bwd_visited: meeting = v; break
        else fwd_queue.enqueue(v)
  else:
    （对称：从 backward 侧扩展，用 predecessors）
  if meeting != None: break
return 由 meeting 拼接的完整路径，或 None
```

## 关键前提

- 必须同时提供 `successors` 与 `predecessors`（反向图）。对稀疏图建议
  直接存双向邻接表；对可"逆着规则推导"的惰性图（如棋局、迷宫），手写
  `predecessors` 往往只多几行代码；
- 若图不是**双连通**（源可达目标，目标反向也可达源），双向 BFS 退化为
  单向 BFS 某方向——本库会正常返回 `None`（见 whitebox 用例"前沿失衡
  切换"）。

## 时间复杂度

- **最好** O(b^(d/2))，比单向 BFS 快指数级；
- **最坏** O(b^d)（目标在图深处、反向图稀疏时没加速）；
- **空间** 同单向 BFS，O(V)。

## 典型场景

1. **RTS 单位寻路**：地图大但起终点位置相对已知；
2. **社交网络"六度分隔"**：从 A 与 B 两端向中间扩展验证连接；
3. **棋类搜索**：已知开局与残局状态，预计算中局对接；
4. **IDA\* 的互补**：IDA\* 省内存但重复扩展，双向 BFS 省时间但需反向图。

## MoonBit API 示例

```moonbit
let adj : Array[Array[Int]] = [[1], [2], [3], []]
let rev : Array[Array[Int]] = [[], [0], [1], [2]]
let path = @directed.bidirectional_bfs(
  0, 3, fn(n) { adj[n] }, fn(n) { rev[n] })
// path == Some([0, 1, 2, 3])
```

## 参考文献

- Pohl, I. (1971). "Bi-directional search." *Machine Intelligence*, 6, 127–140.
  Stanford AI Lab Memo AI-104。
- Russell & Norvig, *AIMA* 第 4 版 3.4.6。
