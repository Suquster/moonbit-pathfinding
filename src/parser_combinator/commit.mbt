// commit.mbt —— L1 提交语义（commit / cut）与错误恢复（recover）。
//
// 对应 tasks.md 任务 7.1，落地 design.md §「组件与接口 → 6. 提交语义与错误
// 恢复」。论文出处：消费提交语义源自 Leijen & Meijer 的 Parsec 设计。
//
// 软/硬失败分离（R7）：
//   * 软失败（committed=false）—— 未跨越提交点，`choice` / `alt` 可回溯；
//   * 硬失败（committed=true）—— 跨越提交点后失败，`choice` 立即停止并上抛。

///|
/// `commit`（亦记 `cut`）：把其内部解析器 `p` 范围内的失败提升为**硬失败**。
///
/// 进入 `commit(p)` 后，`p` 的任何失败被标记为 `committed=true`（R7.1）；成功
/// 原样透传。提交透明性（R7.5）：对不含提交点的解析器，投影回 `ParseResult`
/// 时 committed 标志被丢弃，故 `commit(p)` 与 `p` 的可观察结果一致。
pub fn[T] commit(p : Grammar[T]) -> Grammar[T] {
  Grammar::new(fn(ctx, input) {
    match pc_run(p, ctx, input) {
      OOk(v, rest) => OOk(v, rest)
      OFail(pos, e, _) => OFail(pos, e, true)
    }
  })
}

///|
/// `cut`：`commit` 的语义别名（Parsec 习惯写法），二者完全等价。
pub fn[T] cut(p : Grammar[T]) -> Grammar[T] {
  commit(p)
}

///|
/// `choice`：提交感知的择一组合（commit-aware ordered choice）。
///
///   * 某分支成功（`OOk`）→ 立即返回（PEG 有序选择，首个成功即提交）；
///   * 某分支跨越提交点后失败（硬失败）→ 立即停止尝试后续分支并向上传播该
///     硬失败（R7.2）；
///   * 某分支未跨越提交点即失败（软失败）→ 回溯到分支起点继续尝试后续分支
///     （R7.3），并按最远失败合并诊断；
///   * 全部软失败耗尽 → 返回合并后的软失败。
pub fn[T] choice(branches : Array[Grammar[T]]) -> Grammar[T] {
  Grammar::new(fn(ctx, input) {
    let mut acc_pos : Pos? = None
    let mut acc_exp : Array[String] = []
    for b in branches {
      match pc_run(b, ctx, input) {
        OOk(v, rest) => return OOk(v, rest)
        OFail(pos, e, committed) =>
          if committed {
            // 硬失败：停止并向上传播。
            return OFail(pos, e, true)
          } else {
            // 软失败：按最远失败合并诊断后继续。
            match acc_pos {
              None => {
                acc_pos = Some(pos)
                acc_exp = e
              }
              Some(prev) =>
                if pos.offset > prev.offset {
                  acc_pos = Some(pos)
                  acc_exp = e
                } else if pos.offset == prev.offset {
                  let merged : Array[String] = []
                  for x in acc_exp {
                    merged.push(x)
                  }
                  for x in e {
                    merged.push(x)
                  }
                  acc_exp = normalize_expected(merged)
                }
              // pos.offset < prev.offset：保留较远的 prev。
            }
          }
      }
    }
    match acc_pos {
      Some(p) => OFail(p, acc_exp, false)
      None => OFail(input.pos, [], false)
    }
  })
}

///|
/// `recover(p, sync, fallback)`：硬失败的局部错误恢复（error recovery）。
///
///   * `p` 成功 → 原样返回；
///   * `p` 软失败 → 原样透传（交由外层 `choice` 回溯）；
///   * `p` **硬失败** → 记录失败并从进入位置向前扫描，直至 `sync` 同步点成功
///     匹配，越过同步点后以 `fallback` 作为该位置的产出继续解析（R7.4，服务于
///     R11.4 的 JSON 数组/对象元素级恢复）；扫描至输入末尾仍未遇 `sync` 时以
///     `fallback` 在末尾收束。
pub fn[T] recover(
  p : Grammar[T],
  sync : Grammar[Unit],
  fallback : T,
) -> Grammar[T] {
  Grammar::new(fn(ctx, input) {
    match pc_run(p, ctx, input) {
      OOk(v, rest) => OOk(v, rest)
      OFail(pos, e, committed) =>
        if committed {
          // 硬失败：扫描到 sync 同步点之后，以 fallback 续解。
          let mut cur = input
          let mut out : Outcome[T] = OOk(fallback, cur)
          let mut done = false
          while not_done(done) {
            match pc_run(sync, ctx, cur) {
              OOk(_, rest) => {
                out = OOk(fallback, rest)
                done = true
              }
              OFail(_, _, _) =>
                if cur.is_eof() {
                  out = OOk(fallback, cur)
                  done = true
                } else {
                  cur = cur.advance()
                }
            }
          }
          out
        } else {
          OFail(pos, e, committed)
        }
    }
  })
}

///|
/// 内部辅助：循环条件取反（保持 `while` 条件可读，规避 `!` 与裸否定写法）。
fn not_done(done : Bool) -> Bool {
  !done
}
