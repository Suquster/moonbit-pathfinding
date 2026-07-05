# E3 · Slab 分配器（分代句柄）vs 朴素参照 — native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/infra_alloc_bench --target native`
- 实现：`src/infra_alloc/slab.mbt`——对标 Rust `slab` / `slotmap` crate：
  连续槽位数组 + 侵入式 free-list，alloc/free/get 均 O(1)；每槽 32 位代数，
  句柄 `(index, generation)` 释放后永久失效（常数代价 use-after-free 检测）。

## 稳态高 churn（live ≤ 4096、3:1 alloc 偏置趋满占用，n 次混合 alloc/free/get）

| n | Slab（O(1) free-list） | 线性扫描槽池（O(cap)/alloc） | Map 句柄（哈希/操作） |
|---|---|---|---|
| 32000 | 540.16 µs ± 31.93 | 17.87 ms ± 0.76（**33.1×**） | 1.69 ms ± 0.10（3.1×） |
| 128000 | 1.95 ms ± 0.12 | 72.20 ms ± 4.86（**37.0×**） | 6.09 ms ± 0.36（3.1×） |

- 线性扫描槽池是工程中最常见的 ad-hoc 对象池（数组扫空位）——高占用率下
  每次 alloc 扫描近整个容量，随 n 线性放大差距至数量级；
- Map 句柄做法每操作承担哈希+探测+删除整理，Slab 恒定 3.1×；
- Slab 稳态容量不增长（`slab_test.mbt`「churn keeps capacity bounded」：
  10000 次 churn 后 capacity 不变）——逐操作分配归零，满足 E3 KPI。

## 验证

- 三后端（native / wasm-gc / js）全绿、`moon check` 0 告警。
- 差分 PBT：与朴素参照（句柄数组 + 存活标志）逐操作等价 200 迭代
  （alloc/free/set/get/len/iter_live）；分代失效/双重释放/clear 定向锁定。
