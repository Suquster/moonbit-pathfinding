# T1.1 / T1.2 —— 真·wasm / 真·JS 产物验证证据

日期：2026-07-05 · 工具链：moon 0.1.20260629 · node v22.12.0 · wabt(wat2wasm) 1.0.27

## 交付物

| 组件 | 文件 | 说明 |
| --- | --- | --- |
| JS 后端（T1.2） | `src/mini_compiler/js_backend.mbt` | `emit_js_expr` / `emit_js_program` / `compile_ml_to_js`：语义保持的可执行 Node 程序（32 位环绕 `\|0`/`Math.imul`、除零=0 的 `__div`、闭包/递归/元组直映射） |
| wasm 后端（T1.1） | `src/mini_compiler/wasm_backend.mbt` | `emit_wat_module` / `compile_ml_to_wat`：**合法完整 wat 模块**——lambda 提升 + funcref 表 `call_indirect`、线性内存堆（env 链表 / 闭包 `[funcidx, env, isrec]` / 元组）、de Bruijn 词法寻址、`$apply` 递归自指、语义对齐 `$div` |
| 验证驱动 | `src/backend_cli/`（moon run 入口）+ `scripts/verify_backends.sh` | 逐例发射 → node 执行 JS、wat2wasm 汇编 + Node `WebAssembly.instantiate` 执行 wasm → 与解释器 `eval_ml` 输出**逐字符对拍** |
| 仓内回归 | `src/mini_compiler/prop_backend_test.mbt` | 黄金见证（语义编码构造）+ PBT ≥100 迭代（发射全函数/wat 良构/确定性）+ INT_MIN/-1 回归 |

与 `text_backend.mbt`（DISPLAY-ONLY 展示渲染，README 徽章此前的依据）的边界：本次交付的是**真实产物**——外部真实运行时（V8 wasm 引擎 / Node）可执行且与解释器端到端一致。

## 端到端差分结果（scripts/verify_backends.sh）

语料 22 例，覆盖：环绕算术（`1073741824 * 3`、`INT_MIN / -1`）、除零、比较/逻辑/if、
高阶闭包（柯里化、`twice`、部分应用）、遮蔽、`let rec`（阶乘/斐波那契/求和/pow2 环绕）、
嵌套元组、闭包值、元组内递归调用。

```
verify_backends: 22 passed, 0 failed
```

每例均满足：`node prog.js` 输出 == `node run_wasm.mjs prog.wasm` 输出 == `js_show_val(eval_ml(te))`（逐字符）。

## 顺带修复的解释器真实 bug

`INT_MIN / -1` 此前在 `ml_apply_arith` / `fold_arith`（optimize）/ `apply_binop`
（semantics）直接 `a / b`，在 native/wasm 后端触发 `divide result unrepresentable`
陷阱，违反求值全函数契约（R5.8）。现三处统一定义为环绕（`0 - a`），并由
`prop_backend_test.mbt` 的回归测试锁定（解释 / 编译-VM 双路径一致断言）。

## 复现

```bash
./scripts/verify_backends.sh   # 依赖 moon、node、wat2wasm
moon test -p src/mini_compiler # 仓内黄金 + PBT 回归
```
