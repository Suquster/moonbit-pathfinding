// printer.mbt —— 抽象语法树 → 源串（`print_ast`），round-trip 配套打印器。
//
// 对应任务 15.1「最小可用 print_ast 以支撑桩」（design.md `print_ast(ast :
// Ast) -> String`）。与 parser.mbt 保持互逆，为任务 15.3「Property 1：
// Mini_Compiler AST 往返」（`parse(lex(print_ast(ast)))` 还原等价 AST）奠基。
//
// 互逆要点：二元运算节点统一以括号 `( lhs op rhs )` 完全括起，使打印结果与
// 运算符优先级 / 结合性无关，重新解析时必然还原同一树形；`let` 绑定按文法
// 形态 `let name = bound in body` 打印。

///|
/// 将抽象语法树打印为 MiniLet 源串（design.md `print_ast`）。
pub fn print_ast(ast : Ast) -> String {
  match ast {
    Int(n) => n.to_string()
    Var(name) => name
    // 完全括号化以保证「打印再解析」与优先级无关地还原同一树形。
    Bin(op, lhs, rhs) =>
      "(" + print_ast(lhs) + " " + binop_symbol(op) + " " + print_ast(rhs) + ")"
    Let(name, bound, body) =>
      "let " + name + " = " + print_ast(bound) + " in " + print_ast(body)
  }
}

///|
/// 二元运算符的源串符号。
fn binop_symbol(op : BinOp) -> String {
  match op {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Div => "/"
  }
}
