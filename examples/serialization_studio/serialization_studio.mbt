// examples/serialization_studio — runnable demonstration of the
// `src/serialization` direction as a realistic schema workflow: parse and
// validate a .proto covering scalars / repeated / nested / enum / oneof /
// map, round-trip a typed message through wire bytes and JSON, produce
// canonical bytes, detect breaking schema changes, and generate MoonBit
// bindings.
//
// Run with:
//   moon run examples/serialization_studio

///|
fn main {
  println("=== 1. parse + validate .proto (UserProfile) ===")
  let schema = match @ser.parse_proto_full(@ser.demo_proto()) {
    Ok(s) => s
    Err(e) => {
      println("parse error: \{e}")
      return
    }
  }
  match @ser.validate_schema(schema) {
    Ok(_) =>
      println(
        "valid schema: \{schema.messages.length()} messages, \{schema.enums.length()} enums",
      )
    Err(errors) => {
      for e in errors {
        println("schema error: \{e}")
      }
      return
    }
  }
  println("")
  println("=== 2. typed encode/decode round-trip ===")
  let msg = @ser.demo_message()
  let bytes = match @ser.encode_typed(schema, @ser.demo_message_name, msg) {
    Ok(b) => b
    Err(e) => {
      println("encode error: \{e}")
      return
    }
  }
  println("wire size : \{bytes.length()} bytes")
  match @ser.decode_typed(schema, @ser.demo_message_name, bytes) {
    Ok(back) => println("round-trip: decoded == original -> \{back == msg}")
    Err(e) => println("decode error: \{e}")
  }
  println("")
  println("=== 3. canonical bytes + JSON bridge ===")
  match @ser.encode_canonical(schema, @ser.demo_message_name, msg) {
    Ok(canon) =>
      println("canonical : \{canon.length()} bytes (deterministic field order)")
    Err(e) => println("canonical error: \{e}")
  }
  let json = match @ser.encode_json(schema, @ser.demo_message_name, msg) {
    Ok(j) => j
    Err(e) => {
      println("json error: \{e}")
      return
    }
  }
  println("json      : \{json}")
  match @ser.decode_json(schema, @ser.demo_message_name, json) {
    Ok(back) => println("json round-trip ok -> \{back == msg}")
    Err(e) => println("json parse error: \{e}")
  }
  println("")
  println("=== 4. corrupt wire bytes are rejected with an offset ===")
  let corrupt = b"\xff\xff\xff\xff\xff\xff"
  match @ser.decode_typed(schema, @ser.demo_message_name, corrupt) {
    Ok(_) => println("unexpectedly decoded")
    Err(e) => println("rejected  : \{e}")
  }
  println("")
  println("=== 5. schema evolution: breaking-change detection ===")
  let evolved_src = @ser.demo_proto().replace(
    old="int32 id = 1;",
    new="string id = 1;",
  )
  match @ser.parse_proto_full(evolved_src) {
    Ok(evolved) => {
      let breaks = @ser.check_schema_evolution(schema, evolved)
      for b in breaks {
        println("BREAKING field #\{b.field_number}: \{b.reason}")
      }
    }
    Err(e) => println("parse error: \{e}")
  }
  println("")
  println("=== 6. code generation (first lines) ===")
  let code = @ser.gen_moonbit_full(schema)
  let all_lines = code.split("\n").collect()
  let total = all_lines.length()
  for i in 0..<8 {
    if i < total {
      println(all_lines[i].to_owned())
    }
  }
  println("... (\{total} lines total)")
}
