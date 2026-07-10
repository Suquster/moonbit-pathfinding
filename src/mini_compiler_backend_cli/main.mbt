// mini_compiler_backend_cli —— compile(TypedAst, Backend) 外部运行时验证驱动。

///|
let corpus : Array[(String, @mc.Ast)] = [
  (
    "let-add",
    @mc.Let("x", @mc.Int(40), @mc.Bin(@mc.Add, @mc.Var("x"), @mc.Int(2))),
  ),
  ("negative", @mc.Int(-7)),
  ("multiply", @mc.Bin(@mc.Mul, @mc.Int(-6), @mc.Int(7))),
  ("multiply-wrap", @mc.Bin(@mc.Mul, @mc.Int(1073741824), @mc.Int(3))),
  ("divide-zero", @mc.Bin(@mc.Div, @mc.Int(9), @mc.Int(0))),
  ("divide-negative", @mc.Bin(@mc.Div, @mc.Int(-17), @mc.Int(5))),
  (
    "int-min-div-negative-one",
    @mc.Bin(
      @mc.Div,
      @mc.Bin(
        @mc.Sub,
        @mc.Bin(@mc.Sub, @mc.Int(0), @mc.Int(2147483647)),
        @mc.Int(1),
      ),
      @mc.Bin(@mc.Sub, @mc.Int(0), @mc.Int(1)),
    ),
  ),
  ("int-max", @mc.Int(2147483647)),
  (
    "shadow",
    @mc.Let(
      "x",
      @mc.Int(2),
      @mc.Let("x", @mc.Int(9), @mc.Bin(@mc.Sub, @mc.Var("x"), @mc.Int(4))),
    ),
  ),
]

///|
fn hex_digit(n : Int) -> String {
  let digits = "0123456789abcdef"
  digits[n].to_int().unsafe_to_char().to_string()
}

///|
fn bytes_hex(bytes : Bytes) -> String {
  let out = StringBuilder::new()
  for byte in bytes {
    let value = byte.to_int()
    out.write_string(hex_digit((value >> 4) & 0x0f))
    out.write_string(hex_digit(value & 0x0f))
  }
  out.to_string()
}

///|
fn bytes_text(bytes : Bytes) -> String {
  let out = StringBuilder::new()
  for byte in bytes {
    out.write_char(byte.to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
fn main {
  for entry in corpus {
    let (name, ast) = entry
    match @mc.check(ast) {
      Err(_) => println("ERROR " + name)
      Ok(typed) => {
        let expected = match @mc.eval(typed) {
          @mc.IntV(n) => n
        }
        println("=====CASE " + name)
        println("-----EXPECTED")
        println(expected)
        println("-----WASM_HEX")
        println(bytes_hex(@mc.compile(typed, @mc.Wasm)))
        println("-----JS")
        println(bytes_text(@mc.compile(typed, @mc.Js)))
        println("=====ENDCASE")
      }
    }
  }
  println("=====END")
}
