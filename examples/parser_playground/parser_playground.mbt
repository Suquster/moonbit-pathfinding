// examples/parser_playground — runnable demonstration of the
// `src/parser_combinator` direction as a language-tooling workflow: parse
// and evaluate arithmetic with correct precedence/associativity, parse
// JSON with precise error positions, recover from malformed JSON while
// collecting diagnostics, and feed a grammar incrementally chunk by chunk.
//
// Run with:
//   moon run examples/parser_playground

///|
fn main {
  println("=== 1. arithmetic: parse + eval with precedence ===")
  for src in ["1 + 2 * 3", "(1 + 2) * 3", "2 ^ 3 ^ 2", "10 - 4 - 3"] {
    match @pc.parse_and_eval(src) {
      Ok(v) => println("\{src} = \{v}")
      Err(_) => println("\{src} -> parse error")
    }
  }
  println("")
  println("=== 2. expression AST round-trip ===")
  let parser = @pc.expr_parser()
  match parser.parse_string("1 + 2 * 3") {
    Ok(ast, _) =>
      println("printed AST: \{@pc.print_expr(ast)} -> \{@pc.eval_expr(ast)}")
    Fail(_, ..) => println("parse failed")
  }
  println("")
  println("=== 3. JSON parsing with precise errors ===")
  match
    @pc.parse_json(
      "{\"name\": \"router\", \"port\": 8080, \"tags\": [\"a\", \"b\"]}",
    ) {
    Ok(json) => println("parsed json : \{@pc.print_json(json)}")
    Err(_) => println("unexpected parse failure")
  }
  let bad = "{\"name\": \"router\", \"port\": }"
  let jp = @pc.json_parser()
  match jp.explain_failure(bad) {
    Some(msg) => println("bad json    : \{msg}")
    None => println("bad json unexpectedly parsed")
  }
  println("")
  println("=== 4. error recovery collects diagnostics ===")
  let (recovered, errors) = @pc.parse_json_recover("[1, oops, 3]")
  match recovered {
    Some(json) => println("recovered   : \{@pc.print_json(json)}")
    None => println("no recovery possible")
  }
  println("diagnostics : \{errors.length()} error(s) collected")
  println("")
  println("=== 5. incremental parsing, chunk by chunk ===")
  // framed-number protocol: '<' digits '>' — a prefix that fails at the
  // data boundary yields NeedMore instead of a false parse failure.
  let digits = @pc.many1(
    @pc.satisfy(fn(c) { c >= '0' && c <= '9' }, label="digit"),
  )
  let framed = @pc.map(@pc.between(@pc.pchar('<'), digits, @pc.pchar('>')), fn(
    ds,
  ) {
    let mut n = 0
    for c in ds {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
    n
  })
  let grammar = @pc.lift(framed)
  let first = grammar.run_incremental("<12")
  match first {
    NeedMore(_) =>
      println("after chunk '<12': parser needs more input (no false failure)")
    Done(_) => println("after chunk '<12': unexpectedly done")
  }
  let result = @pc.drive(first, ["34", "5>"], closed=true)
  match result.value() {
    Some(n) => println("streamed 3 chunks '<12'+'34'+'5>' -> \{n}")
    None => println("stream parse failed")
  }
}
