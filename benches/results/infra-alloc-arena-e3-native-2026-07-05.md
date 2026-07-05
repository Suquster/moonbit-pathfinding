# E3 · bump/region arena（批量释放型）— native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/infra_alloc_bench --target native`
- 实现：`src/infra_alloc/arena.mbt`——对标 Rust typed-arena / bumpalo 与
  游戏引擎 per-frame arena：对象 bump 进连续存储、稠密下标句柄，`reset`
  O(1) 批量释放整代并保留容量。与 Slab 互补：Slab 面向逐对象 free 的
  churn；Arena 面向「同代同生共死」（AST / 每帧临时图 / 请求作用域）。

## KPI：稳态零增长分配（结构性守卫，非计时）

- `arena_test.mbt`「steady-state: per-generation allocations reach zero
  growth」：首代把容量顶到 1000 后，连续 **200 代** reset+重填，
  `capacity()` 恒定不变、句柄稠密确定（id == 分配序号）——稳态每代底层
  分配严格归零，E3 KPI「high-churn steady-state 零增长分配 + O(1)/操作」
  达成（E3 吞吐数量级证据见 slab 工件 37.0×）。

## 吞吐（64 帧 × 4096 节点临时二叉树，build + 2 次遍历/帧）

| 负载 | Arena SoA（reset 复用） | 朴素每帧新建 boxed 节点图 | 倍率 |
|---|---|---|---|
| 64×4096 | 2.79 ms ± 85.81 µs | 5.40 ms ± 161.29 µs | 1.9× |

- MoonBit GC 的 bump 新生代分配本身很快，故吞吐差距为常数级（1.9×）；
  arena 的核心价值在结构性保证：零稳态分配（无 GC 峰值）+ 稠密句柄
  可直接作并行数组/SoA 索引。

## 验证

- 三后端（native / wasm-gc / js）全绿、`moon check` 0 告警。
- 差分 PBT：与朴素 fresh-array 参照逐操作等价 200 迭代
  （alloc/get/set/reset/len/iter）；bump/reset/容量保留/旧代句柄失效定向。
