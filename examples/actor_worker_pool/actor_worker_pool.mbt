// examples/actor_worker_pool — runnable demonstration of the `src/actor`
// direction as a realistic job-processing service: a supervised worker pool
// with fault injection and automatic restart, deterministic scheduling from
// a seed, message routing strategies, and bounded mailboxes under load.
//
// Run with:
//   moon run examples/actor_worker_pool

///|
fn main {
  println("=== 1. supervised worker pool: faults, restart, deathwatch, ask ===")
  let tasks : Array[@actor.Task] = [
    { id: 1, payload: 10 },
    { id: 2, payload: 20 },
    { id: 3, payload: 30 },
    { id: 4, payload: 40 },
    { id: 5, payload: 50 },
    { id: 6, payload: 60 },
  ]
  let report = @actor.worker_pool_demo(3, tasks, Some(3), 42)
  println("workers      : 3, tasks: \{tasks.length()}, fault on task 3")
  println("completed    : \{report.completed}")
  println("restarts     : \{report.restarts}")
  println(
    "terminations : \{report.terminated_seen.length()} observed via deathwatch",
  )
  for r in report.ask_results {
    match r {
      Replied(v) => println("ask reply    : completed count = \{v}")
      Timeout => println("ask reply    : timeout")
    }
  }
  println("")
  println(
    "=== 2. restart directive: failing actor keeps serving after restart ===",
  )
  let sys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::with_seed(7)
  let behavior = @actor.Behavior::new(fn(_ctx, state, msg) {
    if msg < 0 {
      @actor.ActorOutcome::Errored("rejected negative payload \{msg}")
    } else {
      @actor.ActorOutcome::Updated(state + msg)
    }
  })
  let idle : @actor.Behavior[Int, Int] = @actor.Behavior::new(fn(
    _ctx,
    state,
    _msg,
  ) {
    @actor.ActorOutcome::Updated(state)
  })
  let sup_actor = sys.spawn(0, idle)
  let acc = sys.spawn(0, behavior)
  sys.supervise(
    sup_actor,
    @actor.SupervisorSpec::new(
      OneForOne,
      @actor.RestartIntensity::new(10, 1000),
      Restart,
    ),
    [acc],
  )
  acc.send(5)
  acc.send(-1) // triggers a failure -> supervised restart resets state
  acc.send(7)
  sys.run_until_idle()
  println(
    "final state  : \{sys.state_of(acc).unwrap_or(-1)} (restart reset state, then +7)",
  )
  println("restart count: \{sys.restart_count(acc)}")
  let status_label = match sys.status_of(acc) {
    Some(Running) => "running"
    Some(Stopped) => "stopped"
    Some(Failed(reason)) => "failed: " + reason
    None => "unknown"
  }
  println("status       : \{status_label}")
  println("")
  println("=== 3. routing strategies over a shared pool ===")
  let rsys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::with_seed(1)
  let count = @actor.Behavior::new(fn(_ctx, state, _msg) {
    @actor.ActorOutcome::Updated(state + 1)
  })
  let w1 = rsys.spawn(0, count)
  let w2 = rsys.spawn(0, count)
  let w3 = rsys.spawn(0, count)
  let rr = @actor.Router::new(RoundRobin, [w1, w2, w3])
  for _i in 0..<9 {
    rr.route(1)
  }
  rsys.run_until_idle()
  let c1 = rsys.state_of(w1).unwrap_or(0)
  let c2 = rsys.state_of(w2).unwrap_or(0)
  let c3 = rsys.state_of(w3).unwrap_or(0)
  println("round-robin  : \{c1} / \{c2} / \{c3} (even spread)")
  let ch = @actor.Router::new(ConsistentHash, [w1, w2, w3])
  let key_owner = ch.worker_for_key("user-alice")
  let again = ch.worker_for_key("user-alice")
  println(
    "consistent   : key 'user-alice' -> actor #\{key_owner.value} (stable: \{key_owner == again})",
  )
  println("")
  println("=== 4. bounded mailbox backpressure ===")
  let bsys : @actor.ActorSystem[Int, Int] = @actor.ActorSystem::with_seed(2)
  let slow = bsys.spawn(0, count, bounded=(2, DropNewest))
  for _i in 0..<5 {
    slow.send(1)
  }
  println(
    "queued (cap 2, DropNewest): pending = \{bsys.pending(slow)} of 5 sent",
  )
  bsys.run_until_idle()
  println("processed    : \{bsys.state_of(slow).unwrap_or(0)}")
}
