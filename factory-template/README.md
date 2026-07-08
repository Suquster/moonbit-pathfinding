# factory-template —— 可复制的 MoonBit 工厂脚手架（H-5，L8 模板化）

本目录把 moonbit-pathfinding 沉淀的工程体系抽成**可直接复制**的新项目模板：
acceptance 门禁 + 黄金向量对拍 + 证据工件目录规范 + 三后端 CI 骨架。

## 套用指南（5 步）

1. **复制骨架**：将本目录内容复制到新仓库根，替换 `moon.mod.tpl`
   中的 `{{MODULE}}`（如 `yourname/yourproject`）并去掉 `.tpl` 后缀。
2. **改名示例包**：`src/example/` 是最小合规包（实现 + 黑盒测试 +
   moon.pkg），按你的领域改名并替换实现；保持「每个公开函数都有
   文档注释 + 黑盒测试」的约定。
3. **接入黄金向量对拍**：把参考实现（Python/Rust/权威数据集）的输出
   固化到 `vectors/*.psv`，测试中逐条 `assert_eq`；向量文件与生成脚本
   （`scripts/gen_vectors.*`）一并入库，保证可再生。
4. **启用门禁**：`scripts/acceptance.sh` 依次执行
   `moon fmt --check` → `moon check --deny-warn` →
   三后端 `moon test --target native/wasm-gc/js` → `moon info`（.mbti
   漂移即 API 演进，必须随提交入库）。CI 直接调用该脚本。
5. **维护证据索引**：每落地一个能力，向 `docs/verification/
   evidence_index.psv` 追加一行 `声明|包路径::测试名|commit`；
   断链由 evidence guard 拦截（参见主仓 `scripts/evidence_guard.ps1`
   与 `src/evidence_index` 引擎）。

## 目录规范

```
factory-template/
├── README.md                 # 本指南
├── moon.mod.tpl         # 模块元数据模板（{{MODULE}} 占位）
├── src/example/              # 最小合规包（实现+测试+moon.pkg）
├── vectors/                  # 黄金向量（psv，与生成脚本同库）
├── scripts/acceptance.sh     # 一键 acceptance 门禁
└── docs/verification/        # 证据索引（声明→测试→commit）
```

## 体系约定（不可裁剪项）

- 零警告：`moon check --deny-warn` 是硬门禁；
- 三后端一致：native / wasm-gc / js 测试全过才算过；
- PBT 常态化：不变量用属性测试（≥100 迭代、种子固定）表达；
- 诚实边界：范围外输入显式返回 `None` / 结构化错误，不静默吞掉；
- 证据可回放：每条能力声明必须挂可执行测试与引入 commit。
