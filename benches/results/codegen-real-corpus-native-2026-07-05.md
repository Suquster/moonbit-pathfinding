# 优化流水线削减率 — 真实程序语料（朴素前端直译，无注入冗余）

| kernel | before | after | reduction | semantics |
| --- | --- | --- | --- | --- |
| poly3_naive | 11 | 9 | 18.181818181818183% | true |
| idx2d_addr_twice | 13 | 7 | 46.15384615384615% | true |
| bilerp_weights | 16 | 13 | 18.75% | true |
| det2x2_pair | 8 | 5 | 37.5% | true |
| dot3_unrolled | 10 | 6 | 40% | true |
| checksum4_unrolled | 12 | 8 | 33.333333333333336% | true |
| fixed_scale_debug | 10 | 3 | 70% | true |
| abs_diff_diamond | 10 | 9 | 10% | true |
| clamp_nested | 12 | 8 | 33.333333333333336% | true |
| norm1_4_naive | 15 | 8 | 46.666666666666664% | true |

- 总指令数: before=117 after=76
- 总削减率: 35.042735042735046%（门禁 ≥30%）
- 优化前后全路径语义对拍一致: true


## 复现方式

```bash
moon bench -p benches/codegen_bench --target native
```

- 采集时间（UTC）: 2026-07-05
- 语料：10 个手写真实内核（朴素前端直译，无注入冗余）
- 本语料曾暴露 φ 落点重建缺陷（CopyProp 改写 φ 实参后按首实参推断变量名失效），已修复于 src/codegen_infra/evaluate.mbt
