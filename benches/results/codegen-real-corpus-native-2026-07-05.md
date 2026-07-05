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
| branch_blend_diamond | 20 | 13 | 35% | true |
| norm1_4_naive | 15 | 8 | 46.666666666666664% | true |

- 总指令数: before=137 after=83
- 总削减率: 39.416058394160586%（门禁 ≥30%）
- 优化前后全路径语义对拍一致: true

