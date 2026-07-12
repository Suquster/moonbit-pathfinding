// examples/regex_toolkit — runnable demonstration of the
// `src/regex_engine` direction on a realistic log-scrubbing task:
// extraction with named groups, redaction via replace_all, tokenizing via
// split, and a ReDoS-resistant run of a classically catastrophic pattern.
//
// Run with:
//   moon run examples/regex_toolkit

///|
fn compile(pattern : String) -> @re.Pattern {
  match @re.Pattern::compile(pattern) {
    Ok(p) => p
    Err(e) => abort("failed to compile /\{pattern}/: error at \{e.pos()}")
  }
}

///|
fn slice(text : String, m : @re.Match) -> String {
  let sb = StringBuilder::new()
  let chars = text.to_array()
  for i in m.start..<m.end {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
fn extraction_demo(log_line : String) -> Unit {
  println("=== extraction: IPv4 + status code from an access log ===")
  println("input : \{log_line}")
  let ip = compile(@re.demo_ipv4())
  match ip.find(log_line) {
    Some(m) => println("client ip    : \{slice(log_line, m)}")
    None => println("client ip    : <none>")
  }
  let status = compile(" (?<code>[1-5][0-9][0-9]) ")
  match status.captures(log_line) {
    Some(caps) =>
      match caps.name("code") {
        Some(m) => println("status code  : \{slice(log_line, m)}")
        None => println("status code  : <none>")
      }
    None => println("status code  : <none>")
  }
  println("")
}

///|
fn redaction_demo() -> Unit {
  println("=== redaction: scrub emails and IPs before shipping logs ===")
  let text = "user alice@example.com logged in from 10.0.42.7; admin bob@corp.io from 192.168.1.13"
  println("input : \{text}")
  let email = compile(@re.demo_email())
  let ip = compile(@re.demo_ipv4())
  let pass1 = email.replace_all(text, "<email>")
  let pass2 = ip.replace_all(pass1, "<ip>")
  println("output: \{pass2}")
  println(
    "emails found: \{email.find_all(text).length()}, ips found: \{ip.find_all(text).length()}",
  )
  println("")
}

///|
fn split_demo() -> Unit {
  println("=== split: CSV-ish tokenizing with a delimiter class ===")
  let row = "dijkstra, astar;bidirectional  hub-labels,cch"
  let sep = compile("[,;\\s]+")
  let fields = sep.split(row)
  println("input : \{row}")
  let sb = StringBuilder::new()
  sb.write_string("[")
  for i in 0..<fields.length() {
    if i > 0 {
      sb.write_string(", ")
    }
    sb.write_string(fields[i])
  }
  sb.write_string("]")
  println("fields: \{sb.to_string()}")
  println("")
}

///|
fn redos_demo() -> Unit {
  println("=== ReDoS resistance: (a|a)*b vs 30 a's + '!' ===")
  let evil = compile("(a|a)*b")
  let sb = StringBuilder::new()
  for _ in 0..<30 {
    sb.write_char('a')
  }
  sb.write_char('!')
  let input = sb.to_string()
  let matched = evil.is_match(input)
  println("pattern: (a|a)*b  input: a^30 + '!'")
  println(
    "matched: \{matched} — completed instantly: the default engine is the linear-time Pike VM / lazy DFA, not exponential backtracking",
  )
}

///|
fn main {
  extraction_demo(
    "203.0.113.9 - - [12/Jul/2026:14:00:07] \"GET /route HTTP/1.1\" 200 6417",
  )
  redaction_demo()
  split_demo()
  redos_demo()
}
