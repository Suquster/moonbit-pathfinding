// examples/dst_explorer — runnable demonstration of the `src/dst` direction
// as a realistic distributed-systems test bench: run a seeded replication
// scenario deterministically, inject partition/crash faults, explore
// schedules with DPOR to hunt consistency violations, shrink a failing
// scenario to a minimal repro, and check a register history for
// linearizability.
//
// Run with:
//   moon run examples/dst_explorer

///|
fn main {
  println("=== 1. deterministic replication run (3 replicas, seed 42) ===")
  let scenario = @dst.demo_replication_scenario(3)
  let r1 = @dst.run_des(42, scenario)
  let r2 = @dst.run_des(42, scenario)
  println("status      : \{r1.status}")
  println("trace events: \{r1.trace.length()}")
  println("deterministic replay: same seed -> identical result = \{r1 == r2}")
  println("")
  println("=== 2. replica state after convergence ===")
  for pair in r1.finals {
    let (id, app) = pair
    let log_view = app.log.map(fn(v) { v.to_string() }).join(", ")
    println("replica \{id}: log = [\{log_view}]")
  }
  println("consistency violated: \{@dst.violates_consistency(r1)}")
  println("")
  println("=== 3. fault injection: partition + crash scenario ===")
  let faulty = @dst.demo_partition_crash_scenario()
  let fr = @dst.run_des(7, faulty)
  println("status      : \{fr.status}")
  println("consistency violated: \{@dst.violates_consistency(fr)}")
  println("")
  println("=== 4. DPOR schedule exploration ===")
  let report = @dst.explore_dpor(42, faulty, 64)
  println("schedules explored: \{report.explored}")
  match report.failing {
    Some((seed, trace)) =>
      println("failing schedule found: seed \{seed}, \{trace.length()} events")
    None => println("no failing schedule within budget")
  }
  println("")
  println("=== 5. shrink a failing scenario to a minimal repro ===")
  match @dst.shrink(42, faulty) {
    Minimal(min_sc) =>
      println(
        "minimal repro: \{min_sc.size()} elements (from \{faulty.size()})",
      )
    NotFailing => println("scenario does not fail under default predicate")
  }
  println("")
  println("=== 6. linearizability check on a register history ===")
  let ok_history : Array[@dst.OpEvent] = [
    @dst.OpEvent::invoke(1, "put", 5, 1),
    @dst.OpEvent::ret(1, "put", 5, 2),
    @dst.OpEvent::invoke(2, "get", 5, 3),
    @dst.OpEvent::ret(2, "get", 5, 4),
  ]
  match @dst.is_linearizable(ok_history, { init: 0 }) {
    Linearizable => println("history A: linearizable")
    NotLinearizable(conflict~) =>
      println(
        "history A: NOT linearizable, conflict ops = \{conflict.length()}",
      )
  }
  let bad_history : Array[@dst.OpEvent] = [
    @dst.OpEvent::invoke(1, "put", 5, 1),
    @dst.OpEvent::ret(1, "put", 5, 2),
    @dst.OpEvent::invoke(2, "get", 9, 3),
    @dst.OpEvent::ret(2, "get", 9, 4),
  ]
  match @dst.is_linearizable(bad_history, { init: 0 }) {
    Linearizable => println("history B: linearizable")
    NotLinearizable(conflict~) =>
      println(
        "history B: NOT linearizable (stale read), conflict ops = \{conflict.length()}",
      )
  }
}
