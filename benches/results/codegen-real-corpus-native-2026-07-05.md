# 优化流水线削减率 — 真实程序语料（朴素前端直译，无注入冗余）

| kernel | before | after | reduction | semantics |
| --- | --- | --- | --- | --- |
| poly3_naive | 11 | 9 | 18.181818181818183% | true |
| idx2d_addr_twice | 13 | 5 | 61.53846153846154% | true |
| bilerp_weights | 16 | 12 | 25% | true |
| det2x2_pair | 8 | 5 | 37.5% | true |
| dot3_unrolled | 10 | 6 | 40% | true |
| checksum4_unrolled | 12 | 8 | 33.333333333333336% | true |
| fixed_scale_debug | 10 | 3 | 70% | true |
| abs_diff_diamond | 10 | 7 | 30% | true |
| clamp_nested | 12 | 7 | 41.666666666666664% | true |
| norm1_4_naive | 15 | 8 | 46.666666666666664% | true |

- 总指令数: before=117 after=70
- 总削减率: 40.17094017094017%（门禁 ≥30%）
- 优化前后全路径语义对拍一致: true


## 复现方式

```bash
moon bench -p benches/codegen_bench --target native
```

- 采集时间（UTC）: 2026-07-05
- 语料：10 个手写真实内核（朴素前端直译，无注入冗余）
- 优化能力：SCCP + GVN（交换律规范化）+ 代数恒等化简（a+0/a*1/a*0/a-a 等）+ CopyProp + DCE
