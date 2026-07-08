# h6-fixed-point —— 不动点示范案例（H-6，L9）

用本仓库自己的工厂流程孵化一个**最小新领域包**，全流程可复现，
证明「工厂能生产工厂」（F(F)）：模板 → 选题 → 向量对拍 → 门禁全绿。

## 可复现回放（每步均可照做）

1. **套用模板**（来源 `factory-template/`，commit 296a0df）：
   ```bash
   cp -r factory-template/* case-studies/h6-fixed-point/
   mv moon.mod.tpl moon.mod   # 替换 {{MODULE}} 为 Suquster/h6-luhn
   ```
2. **backlog 选题**：Luhn 校验和（ISO/IEC 7812-1 附录 B）——
   mooncakes 索引（docs/verification/mooncakes_index.psv）中零覆盖的
   校验和域，最小而真实。
3. **黄金向量对拍**：`scripts/gen_vectors.py`（参考实现按标准附录 B）
   再生 `vectors/luhn.psv`（9 条：6 条判定 + 3 条校验位）；
   测试逐条断言，另加 0..999 全量「主体+校验位必然通过、
   其余 9 个校验位必然失败」属性遍历。
4. **门禁全绿**：
   ```bash
   bash scripts/acceptance.sh
   # [1/4] moon fmt --check           → 通过
   # [2/4] moon check --deny-warn     → 0 警告 0 错误
   # [3/4] moon test ×3 后端          → 3/3 × native/wasm-gc/js 全过
   # [4/4] moon info                  → .mbti 无未提交漂移
   # acceptance: ALL GREEN
   ```

## 孵化中发现并修复的真实缺陷

首轮门禁失败：`luhn_check_digit("")` 未守卫空主体（追加占位 0 后
变成合法输入 "0"），违反「诚实边界」约定 —— 测试红、补守卫、复绿。
这正是流程的价值证据：门禁在孵化物上第一时间拦下了边界缺陷。

## 不动点论证

- 模板由主仓流程抽取（H-5），孵化物又完整通过同一套门禁（本案例）；
- 孵化物的证据三元组同样进入 `docs/verification/evidence_index.psv`；
- 因此流程 F 作用于自身产物仍收敛于同样的质量不变量：F(F) 成立。
