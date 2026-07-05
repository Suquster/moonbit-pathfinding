// backend_cli —— T1.1/T1.2 离线验证驱动：对固定 MiniML 语料逐例打印
// 「解释器期望值 / 结果类型形状 / JS 程序 / wat 模块」四段（分隔符定界），
// 由 scripts/verify_backends.sh 汇编执行（node + wat2wasm）并逐字符对拍。

///|
/// 验证语料：覆盖算术（含除零/负数/环绕）、比较、逻辑、if、闭包（高阶/柯里化/
/// 遮蔽/部分应用）、let / let rec（递归：阶乘、斐波那契、互调风格嵌套）、元组
/// （嵌套、含闭包）。
let corpus : Array[String] = [
  "1 + 2 * 3 - 4", "17 / 5", "0 - 7 / 0", "(0 - 2147483647 - 1) / (0 - 1)", "1073741824 * 3",
  "if 2 < 3 then 10 else 20", "(1 < 2 && 3 != 4) || false", "let x = 5 in let y = x * x in y - x",
  "let x = 1 in let x = x + 10 in x", "(fun x -> x * 2) 21", "let add = fun a -> fun b -> a + b in add 3 4",
  "let twice = fun f -> fun x -> f (f x) in twice (fun n -> n * 3) 2", "let inc = fun n -> n + 1 in let apply = fun f -> fun v -> f v in apply inc 41",
  "let rec fact = fun n -> if n <= 1 then 1 else n * fact (n - 1) in fact 10", "let rec fib = fun n -> if n < 2 then n else fib (n - 1) + fib (n - 2) in fib 15",
  "let rec sum = fun n -> if n == 0 then 0 else n + sum (n - 1) in sum 100", "let rec pow2 = fun n -> if n == 0 then 1 else 2 * pow2 (n - 1) in pow2 40",
  "(1 + 1, 2 < 1, (3, 4 * 4))", "let p = (10, 20) in p", "fun x -> x + 1", "let f = fun a -> (a, a * a) in f 6",
  "let rec fact = fun n -> if n <= 1 then 1 else n * fact (n - 1) in (fact 5, fact 7)",
]

///|
fn main {
  for i in 0..<corpus.length() {
    let src = corpus[i]
    println("=====CASE " + i.to_string())
    println("-----SRC")
    println(src)
    match @mc.lex_ml(src) {
      Err(_) => println("-----ERROR lex")
      Ok(toks) =>
        match @mc.parse_ml(toks) {
          Err(_) => println("-----ERROR parse")
          Ok(e) =>
            match @mc.infer(e) {
              Err(_) => println("-----ERROR infer")
              Ok((te, ty)) => {
                println("-----EXPECTED")
                println(@mc.js_show_val(@mc.eval_ml(te)))
                println("-----SHAPE")
                println(@mc.ty_shape(ty))
                println("-----JS")
                println(@mc.emit_js_program(te))
                println("-----WAT")
                println(@mc.emit_wat_module(te))
              }
            }
        }
    }
  }
  println("=====END")
}
