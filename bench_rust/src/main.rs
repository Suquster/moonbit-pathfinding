//! bench_rust —— Rust 侧对比采集器（Requirement 6）。
//!
//! 本程序与 MoonBit 侧（`bench_rust/moon_side`）共享 **逐位一致** 的确定性
//! 随机源与 **完全相同** 的图/查询生成算法，从而保证「相同 64 位种子 → 逐元素
//! 相同的图与查询集」（R6.2）。它有两种运行模式：
//!
//!   * `golden` —— 对给定配置输出「黄金 JSON 图样本」（节点数 / 边 / 查询），
//!     供 `scripts/rust_comparison.ps1` 与 MoonBit 侧逐元素交叉校验。
//!   * `bench`  —— 在 BFS / Dijkstra / A* × 规模 × 出度 × 查询数 的工作负载
//!     矩阵上采集计时（≥5 预热 + ≥30 采样，R6.3），并记录每条查询的结果签名
//!     （跳数 / 代价），供两库结果一致性校验（R6.7）。
//!
//! 公平性约定：
//!   * A* 在一般图上使用 **零启发式**（admissible），等价于一致代价搜索，
//!     与 MoonBit 侧完全一致；方法学声明中显式记录。
//!   * 单个用例的单次采样若超过超时上界（默认 60s，R6.7），标记 `timed_out`
//!     并停止该用例后续采样，避免整套挂起。

use std::time::Instant;

use pathfinding::prelude::{astar, bfs, dijkstra};
use serde::Serialize;

// ─────────────────────────── 确定性随机源 ───────────────────────────
//
// 与 MoonBit `src/infra_pbt/pbt.mbt` 的 `Rng` 逐位一致：xorshift64，仅含移位
// 与异或（无加法 / 乘法），跨语言、跨后端逐位一致。

/// xorshift64 黄金比例常数；当种子为 0 时回退到此非零状态（与 MoonBit 一致）。
const DEFAULT_SEED: u64 = 0x9E37_79B9_7F4A_7C15;

/// 权重取值闭区间 `[WEIGHT_MIN, WEIGHT_MAX]`（与 MoonBit 侧一致）。
const WEIGHT_MIN: i64 = 1;
const WEIGHT_MAX: i64 = 100;

/// 与 MoonBit `Rng` 逐位一致的确定性伪随机源。
struct Rng {
    state: u64,
}

impl Rng {
    /// 以给定种子构造；种子为 0 时回退到非零默认常数（避免 xorshift64 零不动点）。
    fn new(seed: u64) -> Self {
        let state = if seed == 0 { DEFAULT_SEED } else { seed };
        Rng { state }
    }

    /// 推进状态并返回下一个 64 位随机字（xorshift64）。
    fn next_word(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.state = x;
        x
    }

    /// 返回 `[0, n)` 内的非负整数；当 `n <= 0` 时返回 0（与 MoonBit 一致）。
    fn next_below(&mut self, n: i64) -> i64 {
        if n <= 0 {
            0
        } else {
            (self.next_word() % (n as u64)) as i64
        }
    }

    /// 返回闭区间 `[lo, hi]` 内的整数；当 `lo >= hi` 时返回 `lo`（与 MoonBit 一致）。
    fn next_range(&mut self, lo: i64, hi: i64) -> i64 {
        if lo >= hi {
            lo
        } else {
            lo + self.next_below(hi - lo + 1)
        }
    }
}

// ─────────────────────── 确定性图 / 查询生成 ───────────────────────
//
// 生成顺序在两侧严格一致：先按 `m = n * avg_out_degree` 顺序取边，再按
// `num_queries` 顺序取查询。每条边取数顺序为 u, v, w；每条查询为 s, t。

/// 一个确定性生成的工作负载：节点数 `n`、有向带权边、与查询对。
struct Workload {
    n: i64,
    edges: Vec<(i64, i64, i64)>,
    queries: Vec<(i64, i64)>,
}

/// 与 MoonBit 侧逐元素一致的确定性生成算法。
///
/// * 边数 `m = n * avg_out_degree`；每条边 `u = next_below(n)`、`v = next_below(n)`，
///   若 `v == u` 则 `v = (u + 1) % n`（规避自环），`w = next_range(1, 100)`。
/// * 查询 `s = next_below(n)`、`t = next_below(n)`，共 `num_queries` 条。
fn generate(seed: u64, n: i64, avg_out_degree: i64, num_queries: i64) -> Workload {
    let mut rng = Rng::new(seed);
    let m = n.saturating_mul(avg_out_degree);
    let mut edges: Vec<(i64, i64, i64)> = Vec::with_capacity(m.max(0) as usize);
    let mut i = 0i64;
    while i < m {
        let u = rng.next_below(n);
        let mut v = rng.next_below(n);
        if v == u {
            v = if n > 0 { (u + 1) % n } else { u };
        }
        let w = rng.next_range(WEIGHT_MIN, WEIGHT_MAX);
        edges.push((u, v, w));
        i += 1;
    }
    let mut queries: Vec<(i64, i64)> = Vec::with_capacity(num_queries.max(0) as usize);
    let mut q = 0i64;
    while q < num_queries {
        let s = rng.next_below(n);
        let t = rng.next_below(n);
        queries.push((s, t));
        q += 1;
    }
    Workload { n, edges, queries }
}

/// 由边集构建带权邻接表（successors 视图，供 Dijkstra / A* 复用）。
fn build_weighted_adjacency(w: &Workload) -> Vec<Vec<(usize, u64)>> {
    let mut adj: Vec<Vec<(usize, u64)>> = vec![Vec::new(); w.n.max(0) as usize];
    for &(u, v, wt) in &w.edges {
        adj[u as usize].push((v as usize, wt as u64));
    }
    adj
}

/// 由边集构建无权邻接表（供 BFS 复用，忽略权重）。
fn build_unweighted_adjacency(w: &Workload) -> Vec<Vec<usize>> {
    let mut adj: Vec<Vec<usize>> = vec![Vec::new(); w.n.max(0) as usize];
    for &(u, v, _) in &w.edges {
        adj[u as usize].push(v as usize);
    }
    adj
}

// ─────────────────────────── 结果签名 ───────────────────────────
//
// 结果签名是「跨语言可比的标量」：BFS 取最短跳数（边数），Dijkstra / A* 取最短
// 路径代价；不可达统一记 -1。两库对同一用例的签名序列应逐元素相等（R6.7）。

/// 对一个用例的全部查询计算 BFS 跳数签名。
fn bfs_signatures(adj: &[Vec<usize>], queries: &[(i64, i64)]) -> Vec<i64> {
    let mut out = Vec::with_capacity(queries.len());
    for &(s, t) in queries {
        let su = s as usize;
        let tu = t as usize;
        let res = bfs(&su, |&node| adj[node].iter().copied(), |&node| node == tu);
        match res {
            Some(path) => out.push((path.len() as i64) - 1),
            None => out.push(-1),
        }
    }
    out
}

/// 对一个用例的全部查询计算 Dijkstra 代价签名。
fn dijkstra_signatures(adj: &[Vec<(usize, u64)>], queries: &[(i64, i64)]) -> Vec<i64> {
    let mut out = Vec::with_capacity(queries.len());
    for &(s, t) in queries {
        let su = s as usize;
        let tu = t as usize;
        let res = dijkstra(&su, |&node| adj[node].iter().copied(), |&node| node == tu);
        match res {
            Some((_, cost)) => out.push(cost as i64),
            None => out.push(-1),
        }
    }
    out
}

/// 对一个用例的全部查询计算 A*（零启发式）代价签名。
fn astar_signatures(adj: &[Vec<(usize, u64)>], queries: &[(i64, i64)]) -> Vec<i64> {
    let mut out = Vec::with_capacity(queries.len());
    for &(s, t) in queries {
        let su = s as usize;
        let tu = t as usize;
        let res = astar(
            &su,
            |&node| adj[node].iter().copied(),
            |_| 0u64, // 零启发式：一般图上可采纳，等价一致代价搜索（与 MoonBit 侧一致）。
            |&node| node == tu,
        );
        match res {
            Some((_, cost)) => out.push(cost as i64),
            None => out.push(-1),
        }
    }
    out
}

// ─────────────────────────── 计时采样 ───────────────────────────

/// 一次采样：运行该用例全部查询一遍，返回毫秒耗时。
/// 用 `black_box` 包裹结果，防止编译器消除被测计算（保证计时可信）。
fn time_once<T, F: Fn() -> T>(work: F) -> f64 {
    let start = Instant::now();
    let r = work();
    std::hint::black_box(&r);
    start.elapsed().as_secs_f64() * 1000.0
}

/// 排序后的统计量（毫秒）。
#[derive(Serialize, Clone)]
struct Stats {
    min_ms: f64,
    median_ms: f64,
    mean_ms: f64,
    p95_ms: f64,
    sample_count: usize,
}

/// 计算 min / median / mean / p95（p95 用最近秩法，与 MoonBit `compute_stats` 口径一致）。
fn compute_stats(samples: &[f64]) -> Stats {
    let mut sorted = samples.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let count = sorted.len();
    let median = if count == 0 {
        0.0
    } else if count % 2 == 1 {
        sorted[count / 2]
    } else {
        (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
    };
    let sum: f64 = sorted.iter().sum();
    let mean = if count == 0 { 0.0 } else { sum / count as f64 };
    // 最近秩 p95：rank = ceil(0.95 * count)，索引 rank-1，夹取到合法范围。
    let p95 = if count == 0 {
        0.0
    } else {
        let rank = (0.95 * count as f64).ceil() as usize;
        let idx = rank.saturating_sub(1).min(count - 1);
        sorted[idx]
    };
    Stats {
        min_ms: if count == 0 { 0.0 } else { sorted[0] },
        median_ms: median,
        mean_ms: mean,
        p95_ms: p95,
        sample_count: count,
    }
}

// ─────────────────────────── 报告数据模型 ───────────────────────────

#[derive(Serialize)]
struct CaseResult {
    algorithm: String,
    graph_size: i64,
    avg_out_degree: i64,
    edge_count: usize,
    query_count: usize,
    seed: u64,
    warmup_count: usize,
    timed_out: bool,
    stats: Stats,
    /// 结果签名（每条查询一个标量），供两库一致性交叉校验。
    signatures: Vec<i64>,
}

#[derive(Serialize)]
struct BenchReport {
    schema: String,
    side: String,
    library: String,
    library_version: String,
    rustc_version: String,
    timeout_sec: u64,
    methodology: String,
    cases: Vec<CaseResult>,
}

#[derive(Serialize)]
struct GoldenConfig {
    seed: u64,
    n: i64,
    avg_out_degree: i64,
    num_queries: i64,
    edges: Vec<[i64; 3]>,
    queries: Vec<[i64; 2]>,
}

#[derive(Serialize)]
struct GoldenReport {
    schema: String,
    side: String,
    configs: Vec<GoldenConfig>,
}

// ─────────────────────────── CLI 解析 ───────────────────────────

/// 极简平铺参数解析：`--key value`，支持逗号分隔的整数列表。
struct Args {
    map: std::collections::HashMap<String, String>,
}

impl Args {
    fn parse() -> Self {
        let raw: Vec<String> = std::env::args().skip(1).collect();
        let mut map = std::collections::HashMap::new();
        let mut i = 0;
        while i < raw.len() {
            let a = &raw[i];
            if let Some(key) = a.strip_prefix("--") {
                if i + 1 < raw.len() && !raw[i + 1].starts_with("--") {
                    map.insert(key.to_string(), raw[i + 1].clone());
                    i += 2;
                } else {
                    map.insert(key.to_string(), "true".to_string());
                    i += 1;
                }
            } else {
                i += 1;
            }
        }
        Args { map }
    }

    fn get(&self, key: &str, default: &str) -> String {
        self.map
            .get(key)
            .cloned()
            .unwrap_or_else(|| default.to_string())
    }

    fn get_i64(&self, key: &str, default: i64) -> i64 {
        self.get(key, &default.to_string())
            .parse()
            .unwrap_or(default)
    }

    fn get_u64(&self, key: &str, default: u64) -> u64 {
        self.get(key, &default.to_string())
            .parse()
            .unwrap_or(default)
    }

    fn get_list(&self, key: &str, default: &str) -> Vec<i64> {
        self.get(key, default)
            .split(',')
            .filter_map(|s| s.trim().parse::<i64>().ok())
            .collect()
    }
}

fn rustc_version() -> String {
    std::process::Command::new("rustc")
        .arg("--version")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

/// 写出 JSON 到 `--out` 指定路径；缺省写到 stdout。
fn write_output(args: &Args, json: String) {
    let out = args.get("out", "");
    if out.is_empty() {
        println!("{json}");
    } else {
        std::fs::write(&out, json).expect("failed to write output file");
        eprintln!("[bench_rust] wrote {out}");
    }
}

fn run_golden(args: &Args) {
    let seed = args.get_u64("seed", 0x1234_5678_9ABC_DEF0);
    let num_queries = args.get_i64("queries", 100);
    let sizes = args.get_list("golden-sizes", "1000");
    let degrees = args.get_list("degrees", "4,16");
    let mut configs = Vec::new();
    for &n in &sizes {
        for &d in &degrees {
            let w = generate(seed, n, d, num_queries);
            configs.push(GoldenConfig {
                seed,
                n,
                avg_out_degree: d,
                num_queries,
                edges: w.edges.iter().map(|&(u, v, wt)| [u, v, wt]).collect(),
                queries: w.queries.iter().map(|&(s, t)| [s, t]).collect(),
            });
        }
    }
    let report = GoldenReport {
        schema: "moonbit-pathfinding.rust-comparison.golden.v1".to_string(),
        side: "rust".to_string(),
        configs,
    };
    write_output(args, serde_json::to_string(&report).unwrap());
}

fn run_bench(args: &Args) {
    let seed = args.get_u64("seed", 0x1234_5678_9ABC_DEF0);
    let num_queries = args.get_i64("queries", 100);
    let warmup = args.get_i64("warmup", 5).max(5) as usize;
    let samples = args.get_i64("samples", 30).max(30) as usize;
    let timeout_sec = args.get_u64("timeout-sec", 60);
    let sizes = args.get_list("sizes", "1000,10000,100000");
    let degrees = args.get_list("degrees", "4,16");
    let timeout_ms = timeout_sec as f64 * 1000.0;

    let mut cases: Vec<CaseResult> = Vec::new();

    for &n in &sizes {
        for &d in &degrees {
            let w = generate(seed, n, d, num_queries);
            let edge_count = w.edges.len();
            let query_count = w.queries.len();
            let wadj = build_weighted_adjacency(&w);
            let uadj = build_unweighted_adjacency(&w);

            // 三种算法各自的「整批查询」工作闭包与签名计算器。
            let algos: Vec<(&str, Box<dyn Fn() -> Vec<i64>>)> = vec![
                ("BFS", {
                    let uadj = uadj.clone();
                    let q = w.queries.clone();
                    Box::new(move || bfs_signatures(&uadj, &q))
                }),
                ("Dijkstra", {
                    let wadj = wadj.clone();
                    let q = w.queries.clone();
                    Box::new(move || dijkstra_signatures(&wadj, &q))
                }),
                ("A*", {
                    let wadj = wadj.clone();
                    let q = w.queries.clone();
                    Box::new(move || astar_signatures(&wadj, &q))
                }),
            ];

            for (algo, work) in algos {
                eprintln!(
                    "[bench_rust] case algo={algo} n={n} deg={d} edges={edge_count} queries={query_count}"
                );
                // 预热第一拍即检测超时（R6.7），避免大规模用例挂起整套。
                let first = time_once(|| work());
                if first > timeout_ms {
                    eprintln!(
                        "[bench_rust]   TIMEOUT (>{timeout_sec}s) on first run; case excluded."
                    );
                    let sig = work();
                    cases.push(CaseResult {
                        algorithm: algo.to_string(),
                        graph_size: n,
                        avg_out_degree: d,
                        edge_count,
                        query_count,
                        seed,
                        warmup_count: warmup,
                        timed_out: true,
                        stats: compute_stats(&[first]),
                        signatures: sig,
                    });
                    continue;
                }
                // 余下预热（已用一拍）。
                for _ in 1..warmup {
                    let _ = work();
                }
                // 采样。
                let mut times = Vec::with_capacity(samples);
                let mut timed_out = false;
                for _ in 0..samples {
                    let t = time_once(|| work());
                    times.push(t);
                    if t > timeout_ms {
                        timed_out = true;
                        break;
                    }
                }
                let signatures = work();
                cases.push(CaseResult {
                    algorithm: algo.to_string(),
                    graph_size: n,
                    avg_out_degree: d,
                    edge_count,
                    query_count,
                    seed,
                    warmup_count: warmup,
                    timed_out,
                    stats: compute_stats(&times),
                    signatures,
                });
            }
        }
    }

    let report = BenchReport {
        schema: "moonbit-pathfinding.rust-comparison.bench.v1".to_string(),
        side: "rust".to_string(),
        library: "pathfinding".to_string(),
        library_version: "4.11.0".to_string(),
        rustc_version: rustc_version(),
        timeout_sec,
        methodology: format!(
            "Deterministic xorshift64 seed={seed}; edges=n*degree (u,v,w order), queries=(s,t); \
             A* uses zero heuristic (admissible) on general graphs; warmup>={warmup}, samples>={samples}; \
             per-sample = run all queries once; timing via std::time::Instant in ms; timeout {timeout_sec}s per sample."
        ),
        cases,
    };
    write_output(args, serde_json::to_string(&report).unwrap());
}

fn main() {
    let args = Args::parse();
    let mode = args.get("mode", "bench");
    match mode.as_str() {
        "golden" => run_golden(&args),
        "bench" => run_bench(&args),
        other => {
            eprintln!("[bench_rust] unknown mode: {other} (expected 'golden' or 'bench')");
            std::process::exit(2);
        }
    }
}
