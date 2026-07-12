// examples/pbt_fuzz_lab — runnable demonstration of the `src/infra_pbt` +
// `src/infra_fuzz` directions as a testing-lab workflow: check properties
// over generated inputs, watch a false property shrink to a minimal
// counterexample, inspect generator distribution stats, verify an
// encode/decode round-trip law, and generate + shrink random graphs for
// differential fuzzing.
//
// Run with:
//   moon run examples/pbt_fuzz_lab

///|
fn main {
  println("=== 1. a true property holds for all generated inputs ===")
  let gen_small = @pbt.gen_int_range(0, 1000)
  let holds = @pbt.holds_for_all(gen_small, fn(n) { n + n == 2 * n })
  println("forall n in [0,1000): n + n == 2n -> \{holds}")
  println("")
  println("=== 2. a false property shrinks to a minimal counterexample ===")
  // claim: every number is < 500 — false, and shrinking should drive the
  // counterexample down to the boundary 500.
  let result = @pbt.check_with_shrink(
    gen_small,
    fn(n) { n < 500 },
    @pbt.shrink_int,
  )
  match (result.passed, result.counterexample) {
    (false, Some(cex)) =>
      println("property n < 500 failed, shrunk counterexample: \{cex}")
    (true, _) => println("property unexpectedly passed")
    (false, None) => println("failed without counterexample")
  }
  println("")
  println("=== 3. generator distribution stats ===")
  let gen_dice = @pbt.frequency([
    (1, @pbt.gen_int_range(0, 10)),
    (3, @pbt.gen_int_range(10, 100)),
  ])
  let (ok, stats) = @pbt.holds_for_all_stats(gen_dice, fn(_n) { true }, fn(n) {
    if n < 10 {
      "small"
    } else {
      "large"
    }
  })
  println(
    "weighted 1:3 generator over \{stats.total()} samples -> small=\{stats.count("small")}, large=\{stats.count("large")} (ok=\{ok})",
  )
  println("")
  println("=== 4. encode/decode round-trip law ===")
  let rt = @pbt.round_trip(
    @pbt.gen_int_range(0, 65536),
    fn(n) {
      let b = Bytes::makei(2, fn(i) {
        if i == 0 {
          (n / 256 % 256).to_byte()
        } else {
          (n % 256).to_byte()
        }
      })
      b
    },
    fn(b) {
      if b.length() == 2 {
        Some(b[0].to_int() * 256 + b[1].to_int())
      } else {
        None
      }
    },
  )
  println("decode(encode(n)) == n for u16 big-endian: \{rt}")
  println("")
  println("=== 5. random graphs for differential fuzzing ===")
  let rng = @pbt.rng_new(42)
  let g = @fuzz.fuzz_graph_gen(8, 16).generate(rng)
  println("generated graph: \{g.n} nodes, \{g.edges.length()} edges (seed 42)")
  let g2 = @fuzz.fuzz_graph_gen(8, 16).generate(@pbt.rng_new(42))
  println("same seed reproduces identical graph: \{g == g2}")
  println("")
  println("=== 6. structural shrinking of a failing graph ===")
  let candidates = @fuzz.shrink_fuzz_graph(g)
  println("shrink candidates: \{candidates.length()}")
  let mut smaller = 0
  for c in candidates {
    if c.edges.length() < g.edges.length() || c.n < g.n {
      smaller = smaller + 1
    }
  }
  println("all candidates strictly smaller: \{smaller == candidates.length()}")
}
