// pipeline_unit_test.mbt —— 统一流水线（pipeline.mbt）黑盒单元测试，覆盖
// R13.1 / R13.2 / R13.3（任务 11.3）。
//
// 本文件为黑盒测试（`_test.mbt`），仅通过本包 `pub` / `pub(all)` 接口
// （`run_interp` / `run_compiled` / `PipelineResult` / `Val` / `Diagnostic` /
// `DiagKind`）观察流水线行为，不触碰内部实现，亦不修改任何源文件。
//
// 覆盖三类样例：
//   1. 正常源串两路一致（R13.3）：对若干良类型源串，断言解释路径 `run_interp`
//      与编译—执行路径 `run_compiled` 产出彼此相等且等于期望 `Produced(<Val>)`。
//   2. optimize 旗标（R13.1）：开启优化后两路仍一致且语义不变。
//   3. 各阶段错误短路与诊断向上传播（R13.2）：词法 / 语法 / 类型 / 作用域
//      （未绑定变量）错误均以 `Failed(d)` 短路，且两路返回同一诊断。
//
// 注：`PipelineResult` / `Val` / `Diagnostic` / `DiagKind` 均仅 `derive(Eq)`
// （无 `Show`），故统一以 `assert_true(... == ...)` 比较而非 `assert_eq`。
//
// 运行 native 后端前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

///|
/// 断言：对良类型源串 `src`（不开启优化），解释路径与编译路径产出彼此相等，
/// 且均等于期望结果 `expected`（R13.3）。
///
/// 两路共享前端（lex → parse → infer），仅尾部后端不同；对良类型输入应得到
/// 语义相等的运行期值，故以 `PipelineResult`（derive(Eq)）直接比较。
fn assert_both_agree(src : String, expected : PipelineResult) -> Unit raise {
  let ri = run_interp(src)
  let rc = run_compiled(src)
  assert_true(ri == expected)
  assert_true(rc == expected)
  assert_true(ri == rc)
}

///|
/// 正常源串两路一致（R13.3）：算术优先级、条件、let rec 递归、lambda 应用与
/// 比较运算，五个良类型样例均断言两路彼此相等且等于期望 `Produced(<Val>)`。
test "pipeline: well-typed sources agree on both paths" {
  // 算术优先级：1 + 2 * 3 = 1 + 6 = 7。
  assert_both_agree("1 + 2 * 3", Produced(VInt(7)))
  // 条件：1 < 2 为真，取 then 分支 10。
  assert_both_agree("if 1 < 2 then 10 else 20", Produced(VInt(10)))
  // 递归阶乘 f 5 = 120。
  assert_both_agree(
    "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5",
    Produced(VInt(120)),
  )
  // lambda 应用：(fun x -> x + 1) 41 = 42。
  assert_both_agree("(fun x -> x + 1) 41", Produced(VInt(42)))
  // 比较运算结果为布尔：1 < 2 = true。
  assert_both_agree("1 < 2", Produced(VBool(true)))
}

///|
/// optimize 旗标（R13.1）：开启优化后两路仍彼此一致且语义不变。
/// `let x = 99 in 1 + 2`：未使用的绑定 x 不影响结果，常量折叠后仍为 3。
test "pipeline: optimize flag preserves semantics and two-path agreement" {
  let expected : PipelineResult = Produced(VInt(3))
  let ri = run_interp("let x = 99 in 1 + 2", optimize=true)
  let rc = run_compiled("let x = 99 in 1 + 2", optimize=true)
  assert_true(ri == expected)
  assert_true(rc == expected)
  assert_true(ri == rc)
}

///|
/// 词法错误短路（R13.2）：`@` 不属 MiniML 字母表，前端在词法阶段即以
/// `LexError` 短路，两路返回同一 `Failed(d)`。
test "pipeline: lexical error short-circuits with LexError on both paths" {
  let src = "1 @ 2"
  let ri = run_interp(src)
  let rc = run_compiled(src)
  // 两路在共享前端短路，应返回完全相同的失败诊断。
  assert_true(ri == rc)
  match ri {
    Failed(d) => assert_true(d.kind == LexError)
    Produced(_) => fail("expected LexError, got Produced")
  }
}

///|
/// 语法错误短路（R13.2）：`1 +` 运算符后缺操作数，词法合法但不符合文法，
/// 前端在语法阶段以 `SyntaxError` 短路。
test "pipeline: syntax error short-circuits with SyntaxError on both paths" {
  let src = "1 +"
  let ri = run_interp(src)
  let rc = run_compiled(src)
  assert_true(ri == rc)
  match ri {
    Failed(d) => assert_true(d.kind == SyntaxError)
    Produced(_) => fail("expected SyntaxError, got Produced")
  }
}

///|
/// 类型错误短路（R13.2）：`1 + true` 算术右操作数为 Bool，不可合一为 Int，
/// 前端在类型推断阶段以 `TypeError` 短路。
test "pipeline: type error short-circuits with TypeError on both paths" {
  let src = "1 + true"
  let ri = run_interp(src)
  let rc = run_compiled(src)
  assert_true(ri == rc)
  match ri {
    Failed(d) => assert_true(d.kind == TypeError)
    Produced(_) => fail("expected TypeError, got Produced")
  }
}

///|
/// 作用域错误向上传播（R13.2）：未绑定变量 `x` 由类型推断即报告为
/// `TypeError`，诊断消息提及变量名 `x`，两路返回同一失败诊断。
test "pipeline: unbound variable propagates a TypeError mentioning the name" {
  let src = "x + 1"
  let ri = run_interp(src)
  let rc = run_compiled(src)
  assert_true(ri == rc)
  match ri {
    Failed(d) => {
      assert_true(d.kind == TypeError)
      assert_true(d.msg.contains("x"))
    }
    Produced(_) => fail("expected TypeError, got Produced")
  }
}
