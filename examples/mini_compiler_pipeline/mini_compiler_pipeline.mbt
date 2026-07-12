// examples/mini_compiler_pipeline — runnable demonstration of the
// `src/mini_compiler` direction: a mini-ML language driven end to end
// through lexing, parsing, Hindley-Milner inference, optimization, a
// bytecode VM (peephole + tail-call optimization) and JS code emission,
// with the interpreter used as a differential oracle.
//
// Run with:
//   moon run examples/mini_compiler_pipeline

///|
/// Run one source program through the full pipeline and print the evidence.
fn pipeline(title : String, src : String) -> Unit {
  println("=== \{title} ===")
  println("source: \{src}")
  match @mc.try_run_demo(src) {
    Ok(trace) => {
      println("principal type : \{trace.principal_type}")
      println("optimized form : \{trace.optimized_form}")
      let interp = show_val(trace.interp_result)
      let vm = show_val(trace.vm_result)
      println("interpreter    : \{interp}")
      println("bytecode VM    : \{vm}")
      println(
        if trace.interp_result == trace.vm_result {
          "cross-check    : interpreter == VM ✓"
        } else {
          "cross-check    : MISMATCH ✗"
        },
      )
    }
    Err(diag) => println(@mc.render_diagnostic(src, diag))
  }
  println("")
}

///|
fn show_val(v : @mc.Val) -> String {
  match v {
    VInt(n) => "VInt(\{n})"
    VBool(b) => "VBool(\{b})"
    VClosure(_, _, _) => "<closure>"
    VTuple(items) => {
      let parts = []
      for item in items {
        parts.push(show_val(item))
      }
      let sb = StringBuilder::new()
      sb.write_string("VTuple(")
      for i in 0..<parts.length() {
        if i > 0 {
          sb.write_string(", ")
        }
        sb.write_string(parts[i])
      }
      sb.write_string(")")
      sb.to_string()
    }
  }
}

///|
/// Demonstrate deep tail recursion running in constant stack via TCO.
fn tco_demo() -> Unit {
  println("=== tail-call optimization ===")
  let src = "let rec sum = fun n -> fun acc -> if n == 0 then acc else sum (n - 1) (acc + n) in sum 100000 0"
  println("source: sum 100000 0 (tail-recursive accumulator)")
  match @mc.lex_ml(src) {
    Ok(tokens) =>
      match @mc.parse_ml(tokens) {
        Ok(expr) =>
          match @mc.infer(expr) {
            Ok((texpr, _)) => {
              let bc = @mc.tco_opt(@mc.peephole_opt(@mc.compile_ml(texpr)))
              let (v, depth) = @mc.run_tco_with_depth(bc, @mc.ml_env_empty())
              println(
                "result         : \{show_val(v)} (100000*100001/2 = 5000050000 wrapped to 32-bit Int)",
              )
              println("max frame depth: \{depth} (constant-stack tail calls)")
            }
            Err(diag) => println(@mc.render_diagnostic(src, diag))
          }
        Err(diag) => println(@mc.render_diagnostic(src, diag))
      }
    Err(diag) => println(@mc.render_diagnostic(src, diag))
  }
  println("")
}

///|
/// Emit JavaScript for a program to show the multi-backend code generator.
fn emit_demo() -> Unit {
  println("=== JS emission ===")
  let src = @mc.demo_fib_src
  match @mc.compile_ml_to_js(src) {
    Ok(js) => {
      println("source: \{src}")
      println("emitted JS:")
      println(js)
    }
    Err(diag) => println(@mc.render_diagnostic(src, diag))
  }
}

///|
fn main {
  pipeline("factorial", @mc.demo_factorial_src)
  pipeline("fibonacci", @mc.demo_fib_src)
  pipeline(
    "higher-order + let-polymorphism", "let id = fun x -> x in (id 1) + (if id true then 1 else 0)",
  )
  pipeline("type error (rendered diagnostic)", "1 + true")
  tco_demo()
  emit_demo()
}
