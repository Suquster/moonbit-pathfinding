// examples/build_pipeline — runnable demonstration of the `src/build_tool`
// direction as a realistic incremental build: parse a makefile-style rule
// set for a multi-module C project, schedule parallel waves, propagate a
// single-header change into a minimal rebuild set, execute actions with an
// up-to-date cache, and bisect a regression range.
//
// Run with:
//   moon run examples/build_pipeline

///|
fn main {
  println("=== 1. parse rules -> dependency graph ===")
  let rules_text = @build.demo_rules()
  println(rules_text)
  let graph = match @build.parse_rules(rules_text) {
    Ok(g) => g
    Err(e) => {
      println("parse error at line \{e.line}: \{e.message}")
      return
    }
  }
  match @build.detect_cycle(graph) {
    Some(cycle) =>
      println(
        "cycle detected: \{cycle.map(fn(t) { t.to_string() }).join(" -> ")}",
      )
    None =>
      println(
        "acyclic: \{graph.nodes.length()} targets, \{graph.edges.length()} edges",
      )
  }
  println("critical path length: \{@build.critical_path_length(graph)}")
  println("")
  println("=== 2. parallel wave schedule (2 jobs) ===")
  let waves = @build.schedule(graph, 2)
  let mut wave_no = 0
  for wave in waves {
    wave_no = wave_no + 1
    println("wave \{wave_no}: \{wave.map(fn(t) { t.to_string() }).join(", ")}")
  }
  println("")
  println("=== 3. incremental rebuild: touch common.h ===")
  let dirty = @build.propagate_dirty(graph, [@build.Target::new("common.h")])
  let minimal = @build.minimal_rebuild_set(graph, [
    @build.Target::new("common.h"),
  ])
  println("dirty closure : \{dirty.map(fn(t) { t.to_string() }).join(", ")}")
  println(
    "minimal set   : \{minimal.length()} of \{graph.nodes.length()} targets rebuilt",
  )
  println("")
  println("=== 4. cached action execution: second run is a no-op ===")
  let actions : Array[@build.Action] = [
    {
      id: "cc_core",
      inputs: ["core_a.c", "common.h"],
      outputs: ["core_a.o"],
      command: "cc -c core_a.c",
    },
    {
      id: "link_app",
      inputs: ["core_a.o"],
      outputs: ["app"],
      command: "cc -o app core_a.o",
    },
  ]
  let sched = @build.build_parallel_schedule(actions, [
    ("core_a.c", "h1"),
    ("common.h", "h2"),
  ])
  let executed : Array[String] = []
  let exec = @build.CallbackExecutor::new(fn(a) {
    executed.push(a.id)
    "out-\{a.id}"
  })
  let log1 = @build.run_actions(sched, exec, @build.BuildLog::new())
  println("first run executed : \{executed.join(", ")}")
  executed.clear()
  let _log2 = @build.run_actions(sched, exec, log1)
  println("second run executed: [\{executed.join(", ")}] (cache hit, skipped)")
  println("")
  println("=== 5. auto-bisect a regression range ===")
  let report = @build.auto_bisect(32, fn(commit) {
    if commit >= 21 {
      @build.BisectVerdict::BisectBad
    } else {
      @build.BisectVerdict::BisectGood
    }
  })
  match report.first_bad {
    Some(bad) =>
      println("first bad commit: \{bad} (probes: \{report.probes.length()})")
    None => println("no bad commit found (probes: \{report.probes.length()})")
  }
}
