// examples/config_diff_ops — runnable demonstration of the
// `src/infra_config` + `src/infra_diff` directions as a realistic ops
// workflow: parse a service TOML/INI config, diff two config revisions into
// unified hunks, apply and revert the patch, three-way merge concurrent
// edits with conflict rendering, and gate a rollout on semver.
//
// Run with:
//   moon run examples/config_diff_ops

///|
fn main {
  println("=== 1. parse service config (TOML) ===")
  let toml_src = "name = \"router\"\nport = 8080\ntimeout = 2.5\ndebug = false\n"
  match @config.toml_parse(toml_src) {
    Some(table) => {
      println("keys: \{table.length()}")
      match @config.toml_get(table, "port") {
        Some(TomlInt(p)) => println("port: \{p}")
        _ => println("port missing")
      }
      match @config.toml_get(table, "timeout") {
        Some(TomlFloat(t)) => println("timeout: \{t}s")
        _ => println("timeout missing")
      }
    }
    None => println("toml parse failed")
  }
  let ini_src = "[server]\nhost = 0.0.0.0\nport = 8080\n[log]\nlevel = info\n"
  match @config.ini_parse(ini_src) {
    Some(sections) => {
      let level = @config.ini_get(sections, "log", "level").unwrap_or("?")
      println("ini [log] level: \{level}")
    }
    None => println("ini parse failed")
  }
  println("")
  println("=== 2. diff two config revisions -> unified patch ===")
  let v1 = ["name = router", "port = 8080", "timeout = 2.5", "debug = false"]
  let v2 = ["name = router", "port = 9090", "timeout = 2.5", "retries = 3"]
  let ops = @diff.diff_lines(v1, v2)
  println("edit distance: \{@diff.edit_distance(ops)}")
  println(@diff.format_unified(v1, v2, context=1))
  println("=== 3. patch apply + revert round-trip ===")
  match @diff.patch_apply(v1, ops) {
    Some(patched) => {
      println("apply ok  : patched == v2 -> \{patched == v2}")
      match @diff.patch_revert(patched, ops) {
        Some(reverted) =>
          println("revert ok : reverted == v1 -> \{reverted == v1}")
        None => println("revert failed")
      }
    }
    None => println("apply failed")
  }
  let hunks = @diff.hunks_of(ops, context=1)
  match @diff.apply_unified(v1, hunks) {
    Some(via_hunks) => println("hunk apply: == v2 -> \{via_hunks == v2}")
    None => println("hunk apply failed")
  }
  println("")
  println("=== 4. three-way merge of concurrent edits ===")
  let base = [
    "# service", "port = 8080", "workers = 4", "level = info", "retries = 1",
  ]
  let ours = [
    "# service", "port = 9090", "workers = 4", "level = info", "retries = 1",
  ]
  let theirs = [
    "# service", "port = 8080", "workers = 4", "level = debug", "retries = 1",
  ]
  let merged = @diff.diff3_merge(base, ours, theirs)
  let (lines, has_conflict) = @diff.render_merge(merged)
  println("disjoint edits -> conflict = \{has_conflict}")
  println("merged: [\{lines.join(", ")}]")
  let theirs2 = [
    "# service", "port = 7070", "workers = 4", "level = info", "retries = 1",
  ]
  let conflicted = @diff.diff3_merge(base, ours, theirs2)
  let (clines, has_conflict2) = @diff.render_merge(conflicted)
  println("conflicting edit on same line -> conflict = \{has_conflict2}")
  for l in clines {
    println("  \{l}")
  }
  println("")
  println("=== 5. semver rollout gate ===")
  let cur = @diff.semver_parse("1.4.2")
  let next = @diff.semver_parse("1.5.0-rc.1+build7")
  match (cur, next) {
    (Some(a), Some(b)) => {
      println("current \{a} vs candidate \{b}")
      println(
        "upgrade allowed (candidate newer): \{@diff.semver_compare(a, b) < 0}",
      )
    }
    _ => println("semver parse failed")
  }
}
