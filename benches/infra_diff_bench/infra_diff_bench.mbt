// infra_diff_bench.mbt —— diff 方向基准：三种行 diff 算法、补丁往返
// 与三方合并在确定性演化文本上的吞吐对比。

///|
fn db_base(n : Int) -> Array[String] {
  let out : Array[String] = []
  for i in 0..<n {
    out.push("line \{i}: value = \{i * 31 % 97}")
  }
  out
}

///|
fn db_mutate(
  base : Array[String],
  stride : Int,
  lo : Int,
  hi : Int,
  tag : String,
) -> Array[String] {
  let out : Array[String] = []
  for i in 0..<base.length() {
    if i >= lo && i < hi && i % stride == 0 {
      out.push("line \{i}: value = changed-\{tag}")
    } else {
      out.push(base[i])
    }
  }
  out
}

///|
test "smoke: patch round-trips and diff3 merges cleanly" {
  let base = db_base(64)
  let mine = db_mutate(base, 7, 0, 32, "a")
  let ops = @diff.diff_lines(base, mine)
  assert_true(@diff.patch_apply(base, ops) is Some(_))
  match @diff.patch_apply(base, ops) {
    Some(applied) => assert_eq(applied.length(), mine.length())
    None => assert_true(false)
  }
  match @diff.patch_revert(mine, ops) {
    Some(reverted) => assert_eq(reverted.length(), base.length())
    None => assert_true(false)
  }
  let theirs = db_mutate(base, 11, 36, 64, "b")
  let (_, has_conflict) = @diff.render_merge(
    @diff.diff3_merge(base, mine, theirs),
  )
  assert_true(has_conflict == false)
}

///|
test "bench: myers / histogram / patience / patch / diff3 throughput" (
  b : @bench.T,
) {
  for n in [256, 1024] {
    let base = db_base(n)
    let mine = db_mutate(base, 7, 0, n / 2, "a")
    let theirs = db_mutate(base, 11, n / 2 + 8, n, "b")
    b.bench(name="diff_lines_myers_\{n}", fn() {
      b.keep(@diff.diff_lines(base, mine).length())
    })
    b.bench(name="diff_histogram_\{n}", fn() {
      b.keep(@diff.diff_histogram(base, mine).length())
    })
    b.bench(name="diff_patience_\{n}", fn() {
      b.keep(@diff.diff_patience(base, mine).length())
    })
    let ops = @diff.diff_lines(base, mine)
    b.bench(name="patch_roundtrip_\{n}", fn() {
      let mut ok = 0
      match @diff.patch_apply(base, ops) {
        Some(applied) =>
          match @diff.patch_revert(applied, ops) {
            Some(_) => ok = ok + 1
            None => ()
          }
        None => ()
      }
      b.keep(ok)
    })
    b.bench(name="diff3_merge_\{n}", fn() {
      b.keep(@diff.diff3_merge(base, mine, theirs).length())
    })
  }
}
