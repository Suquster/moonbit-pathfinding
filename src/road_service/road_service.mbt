// road_service.mbt —— 端到端路网服务样例切片（G-C1）。
//
// 组装链路（全部自家 INFRA 组件，零外部依赖）：
//   1. `parse_road_network` —— 边表文本 `from to weight`（空格分隔，
//      `#` 行注释）解析为邻接结构；
//   2. `RoadService::build` —— CH（Contraction Hierarchies）预处理；
//   3. `RoadService::route` —— CH 双向上行查询 + 延迟样本记录
//      （HdrHistogram，2^-p 相对误差）+ 熔断器护航（连续失败达阈值
//      后短路拒绝，冷却后半开恢复）；
//   4. `route_command` / `run_cli` —— `route --from A --to B` CLI 前端；
//   5. `metrics_snapshot` —— p50/p99 延迟与查询计数（服务可观测面）。

///|
/// 路网：节点清单 + 邻接表（有向带权，权为非负 Int 毫米/毫秒等定点单位）。
pub struct RoadNetwork {
  nodes : Array[String]
  adjacency : Map[String, Array[(String, Int)]]
}

///|
/// 解析边表文本行：`from to weight`；`#` 开头为注释；空行跳过。
/// 权重非法或字段数不足的行进入诊断（不静默丢弃）。
pub fn parse_road_network(
  lines : Array[String],
) -> (RoadNetwork, Array[String]) {
  let nodes : Array[String] = []
  let adjacency : Map[String, Array[(String, Int)]] = Map([])
  let diagnostics : Array[String] = []
  fn note_node(n : String) -> Unit {
    if !nodes.contains(n) {
      nodes.push(n)
    }
    if adjacency.get(n) is None {
      adjacency.set(n, [])
    }
  }

  let mut lineno = 0
  for line in lines {
    lineno = lineno + 1
    if line == "" || line.has_prefix("#") {
      continue
    }
    // 按空格切分（连续空格视作单一分隔）。
    let fields : Array[String] = []
    let mut cur = ""
    for c in line {
      if c == ' ' {
        if cur != "" {
          fields.push(cur)
          cur = ""
        }
      } else {
        cur = cur + c.to_string()
      }
    }
    if cur != "" {
      fields.push(cur)
    }
    if fields.length() != 3 {
      diagnostics.push("line " + lineno.to_string() + ": expected 3 fields")
      continue
    }
    let mut w = 0
    let mut ok = true
    for c in fields[2] {
      let code = c.to_int()
      if code >= '0'.to_int() && code <= '9'.to_int() {
        w = w * 10 + (code - '0'.to_int())
      } else {
        ok = false
        break
      }
    }
    if !ok || fields[2] == "" {
      diagnostics.push("line " + lineno.to_string() + ": bad weight")
      continue
    }
    note_node(fields[0])
    note_node(fields[1])
    adjacency.get(fields[0]).unwrap().push((fields[1], w))
  }
  ({ nodes, adjacency }, diagnostics)
}

///|
/// 路网服务：CH 索引 + 延迟直方图 + 熔断器。
pub struct RoadService {
  ch : @advanced.CHGraph[String, Int]
  latency : @infra_metrics.HdrHistogram
  breaker : @infra_resilience.CircuitBreaker
  mut queries : Int
  mut rejected : Int
}

///|
/// 由路网构建服务：CH 预处理 + 观测/护航组件就位。
pub fn RoadService::build(network : RoadNetwork) -> RoadService {
  let ch = @advanced.ch_preprocess(network.nodes, fn(n) {
    network.adjacency.get(n).unwrap_or([])
  })
  {
    ch,
    latency: @infra_metrics.HdrHistogram::new(7),
    breaker: @infra_resilience.CircuitBreaker::create(3, 1000),
    queries: 0,
    rejected: 0,
  }
}

///|
/// 路由结果。
pub(all) enum RouteOutcome {
  RouteFound(Array[String], Int)
  RouteNotFound
  RouteRejected // 熔断器打开，短路拒绝
} derive(Eq)

///|
/// 单次路由查询：熔断器允许才执行 CH 查询；查询失败（无路）记失败、
/// 成功记成功；`now_ms` 与 `elapsed_ms` 由调用方注入（纯函数边界）。
pub fn RoadService::route(
  self : RoadService,
  from : String,
  to : String,
  now_ms : Int64,
  elapsed_ms : Int64,
) -> RouteOutcome {
  if !self.breaker.allow(now_ms) {
    self.rejected = self.rejected + 1
    return RouteRejected
  }
  self.queries = self.queries + 1
  self.latency.record(elapsed_ms)
  match @advanced.ch_query(self.ch, from, to) {
    Some((path, cost)) => {
      self.breaker.record_success()
      RouteFound(path, cost)
    }
    None => {
      self.breaker.record_failure(now_ms)
      RouteNotFound
    }
  }
}

///|
/// 观测面快照：查询数 / 拒绝数 / p50 / p99 延迟（毫秒）。
pub fn RoadService::metrics_snapshot(
  self : RoadService,
) -> (Int, Int, Int64, Int64) {
  (
    self.queries,
    self.rejected,
    self.latency.value_at_percentile(50.0).unwrap_or(0),
    self.latency.value_at_percentile(99.0).unwrap_or(0),
  )
}

///|
/// `route` 子命令 CLI 定义：`route --from <node> --to <node>`。
pub fn route_command() -> @infra_cli.Command {
  {
    name: "roadd",
    about: "road network routing service (CH-powered)",
    specs: [],
    subcommands: [
      {
        name: "route",
        about: "query shortest route",
        specs: [
          @infra_cli.value_spec("from", "f", "source node", None),
          @infra_cli.value_spec("to", "t", "target node", None),
        ],
        subcommands: [],
      },
    ],
  }
}

///|
/// CLI 入口：解析 argv 并执行路由，返回人类可读输出行。
/// 解析错误 / 缺参 / 未知子命令返回诊断文本（总体函数，不崩溃）。
pub fn run_cli(
  service : RoadService,
  argv : Array[String],
  now_ms : Int64,
  elapsed_ms : Int64,
) -> String {
  match @infra_cli.parse(route_command(), argv) {
    Err(e) => "error: " + e.to_string()
    Ok(parsed) => {
      if !(parsed.command_path == ["route"]) {
        return @infra_cli.help_text(route_command())
      }
      match (parsed.value_of("from"), parsed.value_of("to")) {
        (Some(from), Some(to)) =>
          match service.route(from, to, now_ms, elapsed_ms) {
            RouteFound(path, cost) => {
              let mut out = "route:"
              for p in path {
                out = out + " " + p
              }
              out + " (cost " + cost.to_string() + ")"
            }
            RouteNotFound => "no route: " + from + " -> " + to
            RouteRejected => "rejected: circuit breaker open"
          }
        _ => "error: --from and --to are required"
      }
    }
  }
}
