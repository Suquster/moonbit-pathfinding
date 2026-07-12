/**
 * osm.js —— 真实 OSM 路网模式宿主逻辑。
 *
 * 职责：
 *   1. 加载同源 playground.wasm 并绑定 pg_osm_* 图模式导出层
 *      （src/playground/osm.mbt 的整型句柄协议）。
 *   2. 加载同源 osm-xiamen.json（厦门驾车路网，OSM © 贡献者 / ODbL 1.0），
 *      经 pg_osm_reset / pg_osm_add_edge / pg_osm_build 注入 MoonBit 侧。
 *   3. Canvas 绘制路网（等距经纬度投影），点击吸附最近节点选起终点，
 *      调 pg_osm_route 求最短路径并叠加绘制；对比模式依次跑单向与双向
 *      Dijkstra，展示 settle 节点数与耗时差异（代价必须一致）。
 *
 * 路由计算全部发生在 MoonBit wasm-gc 侧；本文件只做 IO 与绘制。
 */

"use strict";

/** pg_osm_* 导出名清单（与 src/playground/osm.mbt 对应）。 */
const OSM_EXPORT_NAMES = [
  "pg_osm_reset",
  "pg_osm_add_edge",
  "pg_osm_build",
  "pg_osm_route",
  "pg_osm_path_len",
  "pg_osm_path_at",
  "pg_osm_cost",
  "pg_osm_settled",
  "pg_osm_last_error",
];

/** 已绑定的 wasm 导出函数集合。 */
const Wasm = {};

/** 宽容 import 对象（同 app.js：占位函数满足任意 import 需求）。 */
function makeImportObject() {
  const noop = function () {
    return 0;
  };
  const fieldProxy = new Proxy(
    {},
    {
      get() {
        return noop;
      },
    }
  );
  return new Proxy(
    {},
    {
      get() {
        return fieldProxy;
      },
    }
  );
}

/** 在 exports 中解析函数（精确或后缀匹配）。 */
function resolveExport(exports, name) {
  if (typeof exports[name] === "function") {
    return exports[name];
  }
  for (const key of Object.keys(exports)) {
    if (key === name || key.endsWith("/" + name) || key.endsWith("." + name)) {
      if (typeof exports[key] === "function") {
        return exports[key];
      }
    }
  }
  return null;
}

/** 加载 playground.wasm 并绑定 pg_osm_* 导出。 */
async function loadWasm() {
  const imports = makeImportObject();
  const resp = await fetch("playground.wasm");
  if (!resp.ok) {
    throw new Error("无法加载 playground.wasm（HTTP " + resp.status + "）");
  }
  let instance;
  if (typeof WebAssembly.instantiateStreaming === "function") {
    try {
      const res = await WebAssembly.instantiateStreaming(resp.clone(), imports);
      instance = res.instance;
    } catch (_e) {
      const bytes = await resp.arrayBuffer();
      const res = await WebAssembly.instantiate(bytes, imports);
      instance = res.instance;
    }
  } else {
    const bytes = await resp.arrayBuffer();
    const res = await WebAssembly.instantiate(bytes, imports);
    instance = res.instance;
  }
  for (const name of OSM_EXPORT_NAMES) {
    const fn = resolveExport(instance.exports, name);
    if (!fn) {
      throw new Error("wasm 导出缺失：" + name);
    }
    Wasm[name] = fn;
  }
}

/** 路网数据（加载后填充）。 */
const Net = {
  name: "",
  nodeCount: 0,
  lat: null, // Int32Array（纬度 * 1e5）
  lon: null, // Int32Array（经度 * 1e5）
  edges: null, // 扁平 [src, dst, w(dm)] * m
  minLat: 0,
  maxLat: 0,
  minLon: 0,
  maxLon: 0,
};

/** UI 状态。 */
const Ui = {
  start: -1,
  goal: -1,
  path: null, // 最近一次路径的节点数组
  nextClickSetsStart: true,
  busy: false,
};

const $ = (id) => document.getElementById(id);

function setStatus(text) {
  $("osm-status-line").textContent = text;
}

function setState(text) {
  $("osm-hud-state").textContent = text;
}

/** 加载路网 JSON 并注入 MoonBit 侧。 */
async function loadNetwork() {
  setState("下载路网…");
  const resp = await fetch("osm-xiamen.json");
  if (!resp.ok) {
    throw new Error("无法加载 osm-xiamen.json（HTTP " + resp.status + "）");
  }
  const doc = await resp.json();
  Net.name = doc.name;
  Net.nodeCount = doc.node_count;
  Net.lat = Int32Array.from(doc.lat);
  Net.lon = Int32Array.from(doc.lon);
  Net.edges = doc.edges;
  let minLat = Infinity;
  let maxLat = -Infinity;
  let minLon = Infinity;
  let maxLon = -Infinity;
  for (let i = 0; i < Net.nodeCount; i++) {
    if (Net.lat[i] < minLat) minLat = Net.lat[i];
    if (Net.lat[i] > maxLat) maxLat = Net.lat[i];
    if (Net.lon[i] < minLon) minLon = Net.lon[i];
    if (Net.lon[i] > maxLon) maxLon = Net.lon[i];
  }
  Net.minLat = minLat;
  Net.maxLat = maxLat;
  Net.minLon = minLon;
  Net.maxLon = maxLon;

  setState("注入 MoonBit 引擎…");
  if (Wasm.pg_osm_reset(Net.nodeCount) !== 0) {
    throw new Error("pg_osm_reset 失败");
  }
  const m = Net.edges.length;
  for (let i = 0; i < m; i += 3) {
    if (Wasm.pg_osm_add_edge(Net.edges[i], Net.edges[i + 1], Net.edges[i + 2]) !== 0) {
      throw new Error("pg_osm_add_edge 失败（第 " + i / 3 + " 条）");
    }
  }
  if (Wasm.pg_osm_build() !== 0) {
    throw new Error("pg_osm_build 失败");
  }
  $("osm-hud-net").textContent =
    Net.name + " " + Net.nodeCount.toLocaleString() + " 节点 / " +
    (m / 3).toLocaleString() + " 边";
}

/** 经纬度（1e5 定点）→ 画布坐标。纵向翻转（纬度向上）。 */
function project(latI, lonI, w, h) {
  const pad = 10;
  const sx = (w - 2 * pad) / (Net.maxLon - Net.minLon || 1);
  const sy = (h - 2 * pad) / (Net.maxLat - Net.minLat || 1);
  const s = Math.min(sx, sy);
  const cx = pad + ((w - 2 * pad) - s * (Net.maxLon - Net.minLon)) / 2;
  const cy = pad + ((h - 2 * pad) - s * (Net.maxLat - Net.minLat)) / 2;
  return [
    cx + (lonI - Net.minLon) * s,
    h - (cy + (latI - Net.minLat) * s),
  ];
}

/** 画布坐标 → 最近路网节点（线性扫描吸附；12.5 万节点 <10ms）。 */
function nearestNode(px, py, w, h) {
  let best = -1;
  let bestD = Infinity;
  for (let i = 0; i < Net.nodeCount; i++) {
    const [x, y] = project(Net.lat[i], Net.lon[i], w, h);
    const d = (x - px) * (x - px) + (y - py) * (y - py);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/** 绘制整个路网 + 选点 + 路径。 */
function draw() {
  const canvas = $("osm-canvas");
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.fillStyle = "#101418";
  ctx.fillRect(0, 0, w, h);

  // 路网底图
  ctx.strokeStyle = "rgba(110, 168, 254, 0.28)";
  ctx.lineWidth = 0.5;
  ctx.beginPath();
  const m = Net.edges.length;
  for (let i = 0; i < m; i += 3) {
    const a = Net.edges[i];
    const b = Net.edges[i + 1];
    const [x1, y1] = project(Net.lat[a], Net.lon[a], w, h);
    const [x2, y2] = project(Net.lat[b], Net.lon[b], w, h);
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
  }
  ctx.stroke();

  // 最短路径
  if (Ui.path && Ui.path.length > 1) {
    ctx.strokeStyle = "#ffd43b";
    ctx.lineWidth = 3;
    ctx.lineJoin = "round";
    ctx.beginPath();
    for (let i = 0; i < Ui.path.length; i++) {
      const n = Ui.path[i];
      const [x, y] = project(Net.lat[n], Net.lon[n], w, h);
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();
  }

  // 起终点标记
  if (Ui.start >= 0) {
    const [x, y] = project(Net.lat[Ui.start], Net.lon[Ui.start], w, h);
    ctx.fillStyle = "#40c057";
    ctx.beginPath();
    ctx.arc(x, y, 6, 0, Math.PI * 2);
    ctx.fill();
  }
  if (Ui.goal >= 0) {
    const [x, y] = project(Net.lat[Ui.goal], Net.lon[Ui.goal], w, h);
    ctx.fillStyle = "#fa5252";
    ctx.beginPath();
    ctx.arc(x, y, 6, 0, Math.PI * 2);
    ctx.fill();
  }
}

/** 读取最近一次路由的路径节点数组。 */
function readPath() {
  const len = Wasm.pg_osm_path_len();
  if (len < 0) {
    return null;
  }
  const path = new Array(len);
  for (let i = 0; i < len; i++) {
    path[i] = Wasm.pg_osm_path_at(i);
  }
  return path;
}

/** 单算法路由；返回 {costDm, settled, ms, path}。 */
function routeOnce(algo, s, t) {
  const t0 = performance.now();
  const rc = Wasm.pg_osm_route(algo, s, t);
  const ms = performance.now() - t0;
  if (rc !== 0) {
    throw new Error("pg_osm_route 错误码 " + rc);
  }
  return {
    costDm: Wasm.pg_osm_cost(),
    settled: Wasm.pg_osm_settled(),
    ms,
    path: readPath(),
  };
}

/** 求解并刷新 HUD/画布。 */
function solve() {
  if (Ui.start < 0 || Ui.goal < 0 || Ui.busy) {
    return;
  }
  Ui.busy = true;
  setState("求解中…");
  // 让浏览器先渲染状态再计算
  setTimeout(() => {
    try {
      const mode = $("osm-algo-select").value;
      if (mode === "2") {
        const uni = routeOnce(0, Ui.start, Ui.goal);
        const bi = routeOnce(1, Ui.start, Ui.goal);
        Ui.path = bi.path;
        if (uni.costDm !== bi.costDm) {
          setStatus("⚠ 单向/双向代价不一致（不应发生）");
        } else if (bi.costDm < 0) {
          setStatus("目标不可达");
        } else {
          setStatus(
            "对比 · 单向 settle " + uni.settled.toLocaleString() + " 节点 / " +
            uni.ms.toFixed(1) + "ms ↔ 双向 settle " +
            bi.settled.toLocaleString() + " 节点 / " + bi.ms.toFixed(1) +
            "ms（代价一致 ✓）"
          );
        }
        $("osm-hud-dist").textContent =
          bi.costDm < 0 ? "不可达" : (bi.costDm / 10000).toFixed(2) + " km";
        $("osm-hud-settled").textContent =
          uni.settled.toLocaleString() + " → " + bi.settled.toLocaleString();
        $("osm-hud-time").textContent =
          uni.ms.toFixed(1) + " → " + bi.ms.toFixed(1) + " ms";
      } else {
        const algo = mode === "0" ? 0 : 1;
        const r = routeOnce(algo, Ui.start, Ui.goal);
        Ui.path = r.path;
        if (r.costDm < 0) {
          setStatus("目标不可达");
          $("osm-hud-dist").textContent = "不可达";
        } else {
          setStatus(
            (algo === 0 ? "单向" : "双向") + " Dijkstra · 路径 " +
            (r.path ? r.path.length : 0).toLocaleString() + " 节点 · settle " +
            r.settled.toLocaleString() + " 节点"
          );
          $("osm-hud-dist").textContent = (r.costDm / 10000).toFixed(2) + " km";
        }
        $("osm-hud-settled").textContent = r.settled.toLocaleString();
        $("osm-hud-time").textContent = r.ms.toFixed(1) + " ms";
      }
      setState("完成");
    } catch (e) {
      setState("错误");
      setStatus(String(e && e.message ? e.message : e));
    } finally {
      Ui.busy = false;
      draw();
    }
  }, 16);
}

/** 画布点击：吸附最近节点，交替设置起点/终点。 */
function onCanvasClick(ev) {
  if (!Net.nodeCount || Ui.busy) {
    return;
  }
  const canvas = $("osm-canvas");
  const rect = canvas.getBoundingClientRect();
  const px = ((ev.clientX - rect.left) / rect.width) * canvas.width;
  const py = ((ev.clientY - rect.top) / rect.height) * canvas.height;
  const node = nearestNode(px, py, canvas.width, canvas.height);
  if (node < 0) {
    return;
  }
  if (Ui.nextClickSetsStart) {
    Ui.start = node;
    Ui.goal = -1;
    Ui.path = null;
    Ui.nextClickSetsStart = false;
    setStatus("已设起点（节点 " + node + "），再点击设置终点");
  } else {
    Ui.goal = node;
    Ui.nextClickSetsStart = true;
    setStatus("已设终点（节点 " + node + "），求解中…");
  }
  draw();
  if (Ui.start >= 0 && Ui.goal >= 0) {
    solve();
  }
}

/** 随机起终点。 */
function randomPair() {
  if (!Net.nodeCount || Ui.busy) {
    return;
  }
  Ui.start = Math.floor(Math.random() * Net.nodeCount);
  Ui.goal = Math.floor(Math.random() * Net.nodeCount);
  Ui.nextClickSetsStart = true;
  Ui.path = null;
  draw();
  solve();
}

/** 清除选点。 */
function clearPicks() {
  Ui.start = -1;
  Ui.goal = -1;
  Ui.path = null;
  Ui.nextClickSetsStart = true;
  $("osm-hud-dist").textContent = "—";
  $("osm-hud-settled").textContent = "—";
  $("osm-hud-time").textContent = "—";
  setStatus("");
  setState("就绪");
  draw();
}

/** 入口。 */
async function main() {
  try {
    await loadWasm();
    $("osm-engine-state").textContent =
      "MoonBit wasm-gc 引擎已加载（pg_osm_* 图模式导出层）";
  } catch (e) {
    $("osm-engine-state").textContent = "引擎加载失败：" + e.message;
    setState("错误");
    setStatus(String(e.message || e));
    return;
  }
  try {
    await loadNetwork();
  } catch (e) {
    setState("错误");
    setStatus(String(e.message || e));
    return;
  }
  setState("就绪");
  setStatus("点击地图两次设置起点与终点");
  draw();
  $("osm-canvas").addEventListener("click", onCanvasClick);
  $("osm-random-btn").addEventListener("click", randomPair);
  $("osm-clear-btn").addEventListener("click", clearPicks);
}

main();
