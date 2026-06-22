// wasm-gc 导出层（exports.mbt）—— 宿主 JS 与 MoonBit 之间的整型句柄边界
//（任务 26.1）。
//
// 设计依据：design.md §「方向 1 · 1.3 wasm-gc 导出层与体积优化」。
//
// 协议概述（「句柄 + 扁平整型读取」）：
//   受 wasm-gc 跨语言传值限制，导出层不暴露泛型/结构体，而是维持 **单一
//   全局会话句柄**，并固定 `N = Int`、`W = Int` 单态化（design.md 体积优化
//   策略第 2 条）。宿主先以 `pg_reset` 建立网格、用 `pg_set_*` 编辑布局、
//   `pg_select_algo` 选算法，再调用 `pg_compute()` 在 MoonBit 侧一次性物化
//   `StepTrace[Int]`；随后按帧、按数组下标用 `pg_step_*` / `pg_final_path_*`
//   拉取扁平整型数据，避免复杂结构跨边界拷贝。
//
// 零异常路径（design.md 体积优化策略第 3 条 / R1.3）：
//   导出层用 **整型错误码** 取代结构化抛错。所有可能失败的入口返回 0 表示
//   成功、返回非 0 的稳定错误码表示失败；该码由 `@graph.PathError` 五变体
//   稳定映射而来（见下方 `error_code`）。`pg_last_error()` 回放最近一次操作
//   的错误码，使宿主无需结构化异常即可诊断失败原因。缺失/非法的算法选择
//   返回 `InvalidArgument` 码而非静默落空（R1.3）。
//
// 不可达语义（R3.4）：目标在当前布局下不可达时，`pg_final_path_len()` 返回
// `-1`（区别于错误码：此时 `pg_last_error()` 仍为 0，因「不可达」是合法的
// 计算结果而非操作失败）。

///|
/// 操作成功（无错误）的状态码。
let err_ok : Int = 0

///|
/// `@graph.PathError::SourceNotFound` 的稳定整型码。
let err_source_not_found : Int = 1

///|
/// `@graph.PathError::TargetNotFound` 的稳定整型码。
let err_target_not_found : Int = 2

///|
/// `@graph.PathError::Unreachable` 的稳定整型码。
let err_unreachable : Int = 3

///|
/// `@graph.PathError::NegativeCycle` 的稳定整型码。
let err_negative_cycle : Int = 4

///|
/// `@graph.PathError::InvalidArgument` 的稳定整型码（含越界/非法参数/算法
/// 码非法等一切「输入非法」情形）。
let err_invalid_argument : Int = 5

///|
/// 算法码：BFS（与 `PlaygroundAlgo` 及 design.md 协议一一对应）。
let algo_bfs : Int = 0

///|
/// 算法码：DFS。
let algo_dfs : Int = 1

///|
/// 算法码：Dijkstra。
let algo_dijkstra : Int = 2

///|
/// 算法码：A\*。
let algo_astar : Int = 3

///|
/// 算法码：JPS。
let algo_jps : Int = 4

///|
/// `pg_step_flags` 的位标志：bit0 = done（终止帧）。
let flag_done : Int = 1

///|
/// `pg_step_flags` 的位标志：bit1 = found（命中目标帧）。
let flag_found : Int = 2

///|
/// 表示「无对应节点 / None / 越界」的整型哨兵值。
///
/// 用于 `pg_step_current`（None）、各 `*_at` 越界读取与 `pg_final_path_len`
/// 的不可达语义（R3.4）。由于网格节点恒为非负线性下标，`-1` 与任何合法节点
/// 值无歧义。
let sentinel_none : Int = -1

///|
/// 单一全局会话状态（句柄）。
///
/// 字段均为可变，承载导出层在多次调用之间共享的会话：
/// - `grid`：当前网格布局（起点/终点/障碍）。
/// - `algo`：当前选定的可视化算法档。
/// - `trace`：最近一次 `pg_compute` 物化的逐步轨迹；尚未计算时为 `None`。
/// - `last_error`：最近一次操作的错误码（`err_ok` 表示成功）。
struct PgSession {
  mut grid : Grid
  mut algo : PlaygroundAlgo
  mut trace : StepTrace[Int]?
  mut last_error : Int
}

///|
/// 进程级单一会话句柄。
///
/// 以单元素数组承载唯一的可变会话实例（MoonBit 全局可变状态惯用法）。初始
/// 网格为 2×2 全通行、起点左上（下标 0）、终点右下（下标 3），满足 `Grid`
/// 的全部不变量；初始算法为 BFS、尚无轨迹、错误码为成功。直接以结构体字面量
/// 构造（`Grid` 为 `pub(all)`），避免对 `Grid::new` 结果做 `unwrap` 的部分性。
let session : Array[PgSession] = [
  {
    grid: {
      rows: 2,
      cols: 2,
      blocked: Array::make(4, false),
      start: 0,
      goal: 3,
    },
    algo: BFS,
    trace: None,
    last_error: err_ok,
  },
]

///|
/// 取得唯一会话句柄。
fn current() -> PgSession {
  session[0]
}

///|
/// 将 `@graph.PathError` 变体稳定映射为整型错误码（R1.3）。
///
/// 映射关系固定，构成宿主可依赖的稳定 ABI：
/// `SourceNotFound`→1、`TargetNotFound`→2、`Unreachable`→3、
/// `NegativeCycle`→4、`InvalidArgument(_)`→5。
fn error_code(e : @graph.PathError) -> Int {
  match e {
    SourceNotFound => err_source_not_found
    TargetNotFound => err_target_not_found
    Unreachable => err_unreachable
    NegativeCycle => err_negative_cycle
    InvalidArgument(_) => err_invalid_argument
  }
}

///|
/// 将整型算法码解析为 `PlaygroundAlgo`；非法码返回 `None`。
fn algo_from_code(code : Int) -> PlaygroundAlgo? {
  if code == algo_bfs {
    Some(BFS)
  } else if code == algo_dfs {
    Some(DFS)
  } else if code == algo_dijkstra {
    Some(Dijkstra)
  } else if code == algo_astar {
    Some(AStar)
  } else if code == algo_jps {
    Some(JPS)
  } else {
    None
  }
}

///|
/// 取出指定帧的单步状态；轨迹缺失或帧序越界返回 `None`。
///
/// 该辅助仅做只读访问，不修改 `last_error`（由各导出入口按需设置错误码）。
fn step_at(step : Int) -> StepState[Int]? {
  match current().trace {
    Some(tr) =>
      if step >= 0 && step < tr.steps.length() {
        Some(tr.steps[step])
      } else {
        None
      }
    None => None
  }
}

///|
/// 重建一个 `rows`×`cols` 的全通行网格并重置会话（R1.2）。
///
/// 起点默认置于左上角、终点置于右下角，所有障碍清空，旧轨迹一并丢弃。
/// 成功返回 `0`；当行列非正或单元格不足 2 时，`Grid::new` 返回
/// `InvalidArgument`，本函数据此返回对应错误码且不改动既有网格（失败原子性）。
/// 该函数是宿主初始化或「重新开始」按钮的统一入口。
pub fn pg_reset(rows : Int, cols : Int) -> Int {
  let s = current()
  match Grid::new(rows, cols) {
    Ok(g) => {
      s.grid = g
      s.trace = None
      s.last_error = err_ok
      err_ok
    }
    Err(e) => {
      let c = error_code(e)
      s.last_error = c
      c
    }
  }
}

///|
/// 设置 `cell` 的障碍状态：`on != 0` 置为障碍、`on == 0` 置为可通行。
///
/// 参数 `cell` 为目标单元的行主序线性下标。返回 `0` 表示成功（含「目标状态
/// 已满足、无需改动」的幂等情形）；越界、或在起点/终点格上设障碍返回
/// `InvalidArgument` 码且不改动布局。任何成功的状态变更都会清空旧轨迹以
/// 强制下一次 `pg_compute` 重算，保证可视化与布局一致。
pub fn pg_set_obstacle(cell : Int, on : Int) -> Int {
  let s = current()
  let g = s.grid
  // 先做界内校验，避免对越界下标直接索引 `blocked`。
  if cell < 0 || cell >= g.cell_count() {
    s.last_error = err_invalid_argument
    return err_invalid_argument
  }
  let desired = on != 0
  // 目标状态已满足：幂等成功，无需变更。
  if g.blocked[cell] == desired {
    s.last_error = err_ok
    return err_ok
  }
  match g.toggle_obstacle(cell) {
    Ok(ng) => {
      s.grid = ng
      s.trace = None
      s.last_error = err_ok
      err_ok
    }
    Err(e) => {
      let c = error_code(e)
      s.last_error = c
      c
    }
  }
}

///|
/// 将起点移动到 `cell`。
///
/// 参数 `cell` 为目标单元的行主序线性下标。成功返回 `0` 并清空旧轨迹；
/// 越界、落在障碍上或与终点重叠返回 `InvalidArgument` 码且不改动布局
/// （值语义由 `Grid::set_start` 保证，失败时入参网格逐字段不变）。
/// 宿主拖拽起点标记时调用本函数提交新位置。
pub fn pg_set_start(cell : Int) -> Int {
  let s = current()
  match s.grid.set_start(cell) {
    Ok(g) => {
      s.grid = g
      s.trace = None
      s.last_error = err_ok
      err_ok
    }
    Err(e) => {
      let c = error_code(e)
      s.last_error = c
      c
    }
  }
}

///|
/// 将终点移动到 `cell`。
///
/// 参数 `cell` 为目标单元的行主序线性下标。成功返回 `0` 并清空旧轨迹；
/// 越界、落在障碍上或与起点重叠返回 `InvalidArgument` 码且不改动布局
/// （值语义由 `Grid::set_goal` 保证）。宿主拖拽终点标记时调用本函数
/// 提交新位置，随后需重新 `pg_compute` 以刷新轨迹。
pub fn pg_set_goal(cell : Int) -> Int {
  let s = current()
  match s.grid.set_goal(cell) {
    Ok(g) => {
      s.grid = g
      s.trace = None
      s.last_error = err_ok
      err_ok
    }
    Err(e) => {
      let c = error_code(e)
      s.last_error = c
      c
    }
  }
}

///|
/// 选择可视化算法（`0=BFS`、`1=DFS`、`2=Dijkstra`、`3=A*`、`4=JPS`）。
///
/// 参数 `algo_code` 为算法码；成功返回 `0` 并清空旧轨迹，使下一次
/// `pg_compute` 以新算法重新搜索。算法码非法（缺失算法入口）返回
/// `InvalidArgument` 码而非静默落空（R1.3），宿主据此提示用户选择无效。
/// 该映射与 `algo_from_code` 单一事实源保持一致。
pub fn pg_select_algo(algo_code : Int) -> Int {
  let s = current()
  match algo_from_code(algo_code) {
    Some(a) => {
      s.algo = a
      s.trace = None
      s.last_error = err_ok
      err_ok
    }
    None => {
      s.last_error = err_invalid_argument
      err_invalid_argument
    }
  }
}

///|
/// 在当前网格与算法上物化一条逐步轨迹，返回步数 `step_count`（R1.2）。
///
/// 以网格的 4-邻接 successor 与曼哈顿启发式驱动 `trace_search`，将结果缓存
/// 到会话供后续 `pg_step_*` / `pg_final_path_*` 读取。返回值恒为正（起点必被
/// 弹出至少一帧）。约定 `<0` 为错误码：当前五档算法均已实现、算法码在
/// `pg_select_algo` 处已校验，故此处不会落入缺失入口；保留该约定以兼容协议。
pub fn pg_compute() -> Int {
  let s = current()
  let g = s.grid
  let successors = g.to_successors()
  let heuristic = g.manhattan(g.goal)
  let trace = trace_search(s.algo, g.start, g.goal, successors, heuristic)
  let count = trace.steps.length()
  s.trace = Some(trace)
  s.last_error = err_ok
  count
}

///|
/// 读取第 `step` 帧已访问（closed）集合的节点数量。
///
/// 参数 `step` 为帧序号，合法取值范围为 `0 ..< pg_compute()` 返回的步数。
/// 返回值为该帧 closed 集合大小（非负整数），供宿主渲染「已探索」着色层。
/// 当尚未调用 `pg_compute` 物化轨迹、或 `step` 越界时返回哨兵值 `-1`，
/// 并置 `last_error = InvalidArgument` 以与合法的零计数明确区分（R1.2）。
pub fn pg_step_visited_len(step : Int) -> Int {
  let s = current()
  match step_at(step) {
    Some(st) => {
      s.last_error = err_ok
      st.visited.length()
    }
    None => {
      s.last_error = err_invalid_argument
      sentinel_none
    }
  }
}

///|
/// 读取第 `step` 帧已访问列表中线性下标 `i` 处的节点编号。
///
/// 节点编号为网格单元的行主序线性下标（`row * cols + col`）。配合
/// `pg_step_visited_len` 可逐项遍历该帧的 closed 集合。参数 `step` 与 `i`
/// 任一越界、或轨迹尚未物化时返回哨兵值 `-1`，并置
/// `last_error = InvalidArgument`，使宿主能稳定地检测边界而不读到脏数据。
pub fn pg_step_visited_at(step : Int, i : Int) -> Int {
  let s = current()
  match step_at(step) {
    Some(st) =>
      if i >= 0 && i < st.visited.length() {
        s.last_error = err_ok
        st.visited[i]
      } else {
        s.last_error = err_invalid_argument
        sentinel_none
      }
    None => {
      s.last_error = err_invalid_argument
      sentinel_none
    }
  }
}

///|
/// 读取第 `step` 帧待扩展边界（open set / frontier）的节点数量。
///
/// 参数 `step` 为帧序号，合法取值范围为 `0 ..< pg_compute()` 返回的步数。
/// 返回值为该帧 open 集合大小（非负整数），供宿主渲染「待探索」着色层，
/// 直观呈现搜索波前的扩张过程。当尚未物化轨迹、或 `step` 越界时返回哨兵值
/// `-1`，并置 `last_error = InvalidArgument` 以与合法的零计数区分（R1.2）。
pub fn pg_step_frontier_len(step : Int) -> Int {
  let s = current()
  match step_at(step) {
    Some(st) => {
      s.last_error = err_ok
      st.frontier.length()
    }
    None => {
      s.last_error = err_invalid_argument
      sentinel_none
    }
  }
}

///|
/// 读取第 `step` 帧边界（frontier）列表中线性下标 `i` 处的节点编号。
///
/// 节点编号为网格单元的行主序线性下标（`row * cols + col`）。配合
/// `pg_step_frontier_len` 可逐项遍历该帧的 open 集合。参数 `step` 与 `i`
/// 任一越界、或轨迹尚未物化时返回哨兵值 `-1`，并置
/// `last_error = InvalidArgument`，保证宿主侧边界检测的确定性。
pub fn pg_step_frontier_at(step : Int, i : Int) -> Int {
  let s = current()
  match step_at(step) {
    Some(st) =>
      if i >= 0 && i < st.frontier.length() {
        s.last_error = err_ok
        st.frontier[i]
      } else {
        s.last_error = err_invalid_argument
        sentinel_none
      }
    None => {
      s.last_error = err_invalid_argument
      sentinel_none
    }
  }
}

///|
/// 读取第 `step` 帧正在扩展的当前节点编号。
///
/// 节点编号为网格单元的行主序线性下标（`row * cols + col`）。当该帧处于
/// 「未开始」或「已终止」状态、其 `current` 为 `None` 时返回哨兵值 `-1`
/// （此为合法状态，`last_error` 置 0）。当轨迹尚未物化、或 `step` 越界时
/// 同样返回 `-1`，但置 `last_error = InvalidArgument` 以区分错误与无当前节点。
pub fn pg_step_current(step : Int) -> Int {
  let s = current()
  match step_at(step) {
    Some(st) => {
      s.last_error = err_ok
      match st.current {
        Some(n) => n
        None => sentinel_none
      }
    }
    None => {
      s.last_error = err_invalid_argument
      sentinel_none
    }
  }
}

///|
/// 读取第 `step` 帧的位标志：bit0 = done（终止帧）、bit1 = found（命中目标帧）。
///
/// 合法返回取值为 `0..3` 的位掩码：`0` 表示进行中、`1` 表示已终止但未命中、
/// `3` 表示已终止且命中目标。宿主可据此驱动「播放/暂停/完成」UI 状态机。
/// 轨迹缺失或帧越界时返回哨兵值 `-1`（与合法的 0..3 取值无歧义），并置
/// `last_error = InvalidArgument`。
pub fn pg_step_flags(step : Int) -> Int {
  let s = current()
  match step_at(step) {
    Some(st) => {
      s.last_error = err_ok
      let mut flags = 0
      if st.done {
        flags = flags | flag_done
      }
      if st.found {
        flags = flags | flag_found
      }
      flags
    }
    None => {
      s.last_error = err_invalid_argument
      sentinel_none
    }
  }
}

///|
/// 返回最终路径的节点数（含起点与终点）。
///
/// 当轨迹已物化且目标可达时返回路径长度（正整数），`last_error` 置 0。
/// 当目标不可达时返回哨兵值 `-1`（R3.4，此为合法计算结果，`last_error`
/// 仍为 0）。当尚未调用 `pg_compute` 物化轨迹时同样返回 `-1`，但置
/// `last_error = InvalidArgument` 以与「不可达」这一合法结果明确区分。
pub fn pg_final_path_len() -> Int {
  let s = current()
  match s.trace {
    Some(tr) =>
      match tr.final_path {
        Some(path) => {
          s.last_error = err_ok
          path.length()
        }
        // 不可达：合法计算结果，非操作错误。
        None => {
          s.last_error = err_ok
          sentinel_none
        }
      }
    None => {
      s.last_error = err_invalid_argument
      sentinel_none
    }
  }
}

///|
/// 读取最终路径中线性下标 `i` 处的节点编号（含起点与终点）。
///
/// 节点编号为网格单元的行主序线性下标（`row * cols + col`）。配合
/// `pg_final_path_len` 可按 `start → … → goal` 的顺序逐点回放最优路径。
/// 当目标不可达、`i` 越界、或轨迹尚未物化时返回哨兵值 `-1`，并置
/// `last_error = InvalidArgument`，保证宿主遍历的边界安全。
pub fn pg_final_path_at(i : Int) -> Int {
  let s = current()
  match s.trace {
    Some(tr) =>
      match tr.final_path {
        Some(path) =>
          if i >= 0 && i < path.length() {
            s.last_error = err_ok
            path[i]
          } else {
            s.last_error = err_invalid_argument
            sentinel_none
          }
        None => {
          s.last_error = err_invalid_argument
          sentinel_none
        }
      }
    None => {
      s.last_error = err_invalid_argument
      sentinel_none
    }
  }
}

///|
/// 返回最近一次操作的错误码（`0` 表示成功）。
///
/// 错误码由 `@graph.PathError` 变体稳定映射而来（见 `error_code`），供宿主在
/// 不依赖结构化异常的前提下诊断失败原因（R1.3）。该函数为纯读取，不修改
/// 任何会话状态，可在任意 `pg_*` 调用之后立即查询。约定：合法但「无结果」
/// 的情形（如目标不可达）不算错误，此时仍返回 `0`。
pub fn pg_last_error() -> Int {
  current().last_error
}
