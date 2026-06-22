"use strict";

/*
 * 宿主交互脚本（任务 27.1）。设计依据：design.md §「方向 1 · 1.4」。
 *
 * 职责：
 *   1. 通过 MoonBit JS glue / 直接实例化加载同源 playground.wasm，绑定
 *      wasm-gc 导出层（exports.mbt）的整型句柄 API（Requirement 4.3：全部
 *      同源，不请求任何外部网络服务）。
 *   2. 在 Canvas 上渲染网格、扩展过程（已访问 / 边界 / 当前）与最终路径。
 *   3. 支持拖拽起点/终点、点击/拖动切换障碍；非法放置被拒绝、恢复到上一个
 *      有效位置并给出视觉反馈（Requirement 2.1 / 2.2 / 2.3 / 2.5）。
 *   4. 维护滚动 1 秒窗口的 requestAnimationFrame 时间戳队列，每 500ms 刷新
 *      实测 fps、网格规模（行×列）与算法名（Requirement 3.5）；实测帧率低于
 *      60fps 时显示警告但不中断动画（Requirement 3.6）。
 *
 * 注意：本脚本不在 JS 侧重新实现寻路算法 —— 所有计算均委托给 wasm 导出层，
 * 保证可视化结果与库实现一致（避免重复实现导致的逻辑漂移）。
 */

// ============================ 协议常量 ============================
// 与 src/playground/exports.mbt 的稳定 ABI 一一对应。

/** 算法码 → 显示名（与 PlaygroundAlgo 顺序一致）。 */
const ALGO_NAMES = ["BFS", "DFS", "Dijkstra", "A*", "JPS"];

/** pg_step_flags 位标志。 */
const FLAG_DONE = 1;
const FLAG_FOUND = 2;

/** 哨兵：表示 None / 越界 / 不可达。 */
const SENTINEL_NONE = -1;

/** pg_last_error 错误码 → 中文诊断（仅用于状态行展示）。 */
const ERROR_MESSAGES = {
  0: "成功",
  1: "源节点不存在",
  2: "目标节点不存在",
  3: "目标不可达",
  4: "检测到负权环",
  5: "输入参数非法",
};

/** 目标帧率门槛（Requirement 3.6）。 */
const TARGET_FPS = 60;

/** 渲染色板（与 style.css 的 --c-* 变量保持一致）。 */
const COLORS = {
  cell: "#243140",
  wall: "#0a0e13",
  visited: "#2f5d8a",
  frontier: "#c9a227",
  current: "#ff5f56",
  path: "#3fb950",
  start: "#58d68d",
  goal: "#ec5f67",
  gridLine: "#1b2430",
  reject: "#ff5f56",
};

// ============================ wasm 绑定 ============================

/**
 * wasm 导出层方法名清单（exports.mbt 中以 `pub fn` 暴露）。加载完成后逐一
 * 解析为可调用函数，封装进 `Wasm` 对象。
 */
const EXPORT_NAMES = [
  "pg_reset",
  "pg_set_obstacle",
  "pg_set_start",
  "pg_set_goal",
  "pg_select_algo",
  "pg_compute",
  "pg_step_visited_len",
  "pg_step_visited_at",
  "pg_step_frontier_len",
  "pg_step_frontier_at",
  "pg_step_current",
  "pg_step_flags",
  "pg_final_path_len",
  "pg_final_path_at",
  "pg_last_error",
];

/** 已绑定的 wasm 导出函数集合（加载成功后填充）。 */
const Wasm = {};

/**
 * 构造一个「宽容」的 import 对象：用 Proxy 拦截任意 module/field 查找，对
 * 未知导入返回无副作用的占位函数，从而无论 MoonBit wasm-gc 运行时发出何种
 * import 需求都能完成实例化。导出层（exports.mbt）为纯整型逻辑、不打印、
 * 不做 FFI，故占位函数永不会在关键路径被调用。
 */
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

/**
 * 在 wasm 实例的 exports 中解析名为 `name` 的函数。优先精确匹配；找不到时
 * 退化为「以 name 结尾」的模糊匹配，以兼容可能的命名前缀。
 */
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

/**
 * 加载并绑定 wasm。加载顺序（全部同源）：
 *   1. 若存在 MoonBit 生成的 JS glue（同目录 playground.js）且其默认导出
 *      或具名导出提供 `instantiate(imports)` / `exports`，优先使用之。
 *   2. 否则直接 fetch + 实例化同目录 playground.wasm。
 * 返回是否绑定成功。
 */
async function loadWasm() {
  const imports = makeImportObject();
  let exports = null;

  // 路径 1：MoonBit JS glue（若部署流水线已组装）。
  try {
    const glue = await import("./playground.js");
    if (glue) {
      if (typeof glue.instantiate === "function") {
        const inst = await glue.instantiate(imports);
        exports = (inst && inst.exports) || inst;
      } else if (typeof glue.default === "function") {
        const inst = await glue.default(imports);
        exports = (inst && inst.exports) || inst;
      } else if (glue.exports) {
        exports = glue.exports;
      } else if (typeof glue.pg_reset === "function") {
        exports = glue;
      }
    }
  } catch (_e) {
    // glue 不存在或加载失败：回退到直接实例化。
    exports = null;
  }

  // 路径 2：直接实例化 playground.wasm。
  if (!exports) {
    const resp = await fetch("playground.wasm");
    if (!resp.ok) {
      throw new Error("无法加载 playground.wasm（HTTP " + resp.status + "）");
    }
    let instance;
    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        const res = await WebAssembly.instantiateStreaming(
          resp.clone(),
          imports
        );
        instance = res.instance;
      } catch (_e) {
        // 某些服务器未以 application/wasm 提供 MIME；回退到 arrayBuffer。
        const bytes = await resp.arrayBuffer();
        const res = await WebAssembly.instantiate(bytes, imports);
        instance = res.instance;
      }
    } else {
      const bytes = await resp.arrayBuffer();
      const res = await WebAssembly.instantiate(bytes, imports);
      instance = res.instance;
    }
    exports = instance.exports;
  }

  // 绑定导出函数。
  for (const name of EXPORT_NAMES) {
    const fn = resolveExport(exports, name);
    if (!fn) {
      throw new Error("wasm 导出缺失：" + name);
    }
    Wasm[name] = fn;
  }
  return true;
}

// ============================ 应用状态 ============================

/**
 * JS 侧的网格镜像。wasm 为计算与校验的唯一权威；本镜像仅用于渲染，且与
 * wasm 通过 pg_set_* 调用结果严格同步（非法操作被 wasm 拒绝时镜像不变）。
 */
const model = {
  rows: 24,
  cols: 36,
  blocked: new Set(), // 障碍格线性下标集合
  start: 0,
  goal: 24 * 36 - 1,
  algo: 0,
};

/**
 * 当前轨迹（compute 后从 wasm 一次性读入，避免逐帧 O(V) 跨边界拷贝）。
 * - visitedOrder[k]：第 k 步被永久访问（closed）的节点（每步恰好一个）。
 * - flags[k]：第 k 步的位标志。
 * - stepCount：总帧数。
 * - finalPath：可达时的回溯路径节点数组；不可达为 null。
 */
const trace = {
  visitedOrder: [],
  flags: [],
  stepCount: 0,
  finalPath: null,
  reachable: false,
};

/** 动画播放状态。 */
const anim = {
  playing: false,
  /** 当前展示到的帧序（0..stepCount）。stepCount 表示播放完毕。 */
  frame: 0,
  /** 播放速度（步/秒）。 */
  stepsPerSecond: 120,
  /** 上一次推进动画的时间戳（ms），用于按 stepsPerSecond 控速。 */
  lastAdvanceTs: 0,
  /** 帧序推进的小数累加器。 */
  accumulator: 0,
};

/** 帧率测量：滚动 1 秒窗口的 rAF 时间戳队列（Requirement 3.5）。 */
const fpsMeter = {
  timestamps: [],
  lastHudUpdate: 0,
  currentFps: 0,
};

/** 拖拽 / 绘制交互状态。 */
const interaction = {
  mode: null, // "start" | "goal" | "paint" | null
  paintValue: null, // 绘制障碍时的目标状态（true=设障碍）
  /** 拒绝放置的视觉反馈：{ cell, until }（performance.now() 截止时间）。 */
  reject: null,
};

// DOM 引用
let canvas, ctx;
let algoSelect, rowsInput, colsInput, resetBtn;
let playBtn, pauseBtn, stepBtn, restartBtn, clearObstaclesBtn;
let speedInput, speedValue;
let hudFps, hudSize, hudAlgo, hudProgress, hudState, hudWarning;
let statusLine, engineState;

/** 单元格像素尺寸（按画布与网格规模动态计算）。 */
let cellSize = 16;

// ============================ 工具函数 ============================

/** 线性下标 → 行。 */
function rowOf(cell) {
  return Math.floor(cell / model.cols);
}

/** 线性下标 → 列。 */
function colOf(cell) {
  return cell % model.cols;
}

/** 设置状态行文本（isError 为真时以告警色显示）。 */
function setStatus(text, isError) {
  statusLine.textContent = text || "";
  statusLine.classList.toggle("error", !!isError);
}

/** 触发某格的「拒绝放置」红色闪烁反馈（持续 ~450ms）。 */
function flashReject(cell) {
  interaction.reject = { cell, until: performance.now() + 450 };
}

// ============================ 渲染 ============================

/** 依据画布尺寸与网格规模重算单元格像素尺寸，并对齐画布像素宽高。 */
function layoutCanvas() {
  // 画布逻辑分辨率：在不超过容器宽度的前提下，让单元格尽量大但有上限。
  const maxWidth = Math.min(canvas.parentElement.clientWidth - 28, 900);
  const maxCell = 28;
  const minCell = 4;
  let size = Math.floor(maxWidth / model.cols);
  if (size > maxCell) size = maxCell;
  if (size < minCell) size = minCell;
  cellSize = size;
  canvas.width = model.cols * cellSize;
  canvas.height = model.rows * cellSize;
}

/** 绘制单个单元格（填充色）。 */
function fillCell(cell, color) {
  const x = colOf(cell) * cellSize;
  const y = rowOf(cell) * cellSize;
  ctx.fillStyle = color;
  ctx.fillRect(x, y, cellSize, cellSize);
}

/** 在单元格中央绘制文字标记（S / G）。 */
function drawLabel(cell, label, color) {
  const x = colOf(cell) * cellSize;
  const y = rowOf(cell) * cellSize;
  ctx.fillStyle = color;
  ctx.fillRect(x, y, cellSize, cellSize);
  if (cellSize >= 12) {
    ctx.fillStyle = "#0a0e13";
    ctx.font = "bold " + Math.floor(cellSize * 0.6) + "px ui-monospace, monospace";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(label, x + cellSize / 2, y + cellSize / 2 + 1);
  }
}

/** 渲染整帧。 */
function render() {
  const total = model.rows * model.cols;

  // 1. 底层：所有可通行格 / 障碍格。
  ctx.fillStyle = COLORS.cell;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  for (const cell of model.blocked) {
    fillCell(cell, COLORS.wall);
  }

  // 2. 已访问（closed）：取轨迹中已展示帧的 current 序列。
  const shown = Math.min(anim.frame, trace.stepCount);
  for (let k = 0; k < shown; k++) {
    const node = trace.visitedOrder[k];
    if (node !== model.start && node !== model.goal) {
      fillCell(node, COLORS.visited);
    }
  }

  // 3. 边界（open set）：仅读取「当前帧」的 frontier，避免 O(V^2) 重建。
  if (shown > 0 && shown <= trace.stepCount) {
    const stepIdx = shown - 1;
    const flen = Wasm.pg_step_frontier_len(stepIdx);
    if (flen > 0) {
      for (let i = 0; i < flen; i++) {
        const node = Wasm.pg_step_frontier_at(stepIdx, i);
        if (node >= 0 && node !== model.start && node !== model.goal) {
          fillCell(node, COLORS.frontier);
        }
      }
    }
  }

  // 4. 最终路径：动画播放到末尾且目标可达时绘制。
  const finished = anim.frame >= trace.stepCount;
  if (finished && trace.reachable && trace.finalPath) {
    for (const node of trace.finalPath) {
      if (node !== model.start && node !== model.goal) {
        fillCell(node, COLORS.path);
      }
    }
  }

  // 5. 当前扩展节点高亮（动画进行中）。
  if (shown > 0 && shown <= trace.stepCount && !finished) {
    const cur = trace.visitedOrder[shown - 1];
    if (cur >= 0 && cur !== model.start && cur !== model.goal) {
      fillCell(cur, COLORS.current);
    }
  }

  // 6. 起点 / 终点标记（始终最上层）。
  drawLabel(model.start, "S", COLORS.start);
  drawLabel(model.goal, "G", COLORS.goal);

  // 7. 拒绝放置的红色闪烁反馈。
  if (interaction.reject && performance.now() < interaction.reject.until) {
    const cell = interaction.reject.cell;
    if (cell >= 0 && cell < total) {
      const x = colOf(cell) * cellSize;
      const y = rowOf(cell) * cellSize;
      ctx.strokeStyle = COLORS.reject;
      ctx.lineWidth = Math.max(2, Math.floor(cellSize * 0.18));
      ctx.strokeRect(x + 1, y + 1, cellSize - 2, cellSize - 2);
    }
  } else if (interaction.reject) {
    interaction.reject = null;
  }

  // 8. 网格线（仅在单元格足够大时绘制，避免小网格糊成一片）。
  if (cellSize >= 10) {
    ctx.strokeStyle = COLORS.gridLine;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let c = 0; c <= model.cols; c++) {
      const x = c * cellSize + 0.5;
      ctx.moveTo(x, 0);
      ctx.lineTo(x, canvas.height);
    }
    for (let r = 0; r <= model.rows; r++) {
      const y = r * cellSize + 0.5;
      ctx.moveTo(0, y);
      ctx.lineTo(canvas.width, y);
    }
    ctx.stroke();
  }
}

// ============================ 计算与轨迹读取 ============================

/**
 * 在 wasm 侧物化当前布局/算法的逐步轨迹，并把每步的 current/flags 一次性
 * 读入 JS（视为 O(stepCount)）。最终路径亦一次性读入。重置动画到起始帧。
 */
function recompute() {
  if (!Wasm.pg_compute) return;
  const stepCount = Wasm.pg_compute();
  if (stepCount < 0) {
    setStatus("计算失败：" + describeError(), true);
    return;
  }
  trace.stepCount = stepCount;
  trace.visitedOrder = new Array(stepCount);
  trace.flags = new Array(stepCount);
  for (let s = 0; s < stepCount; s++) {
    trace.visitedOrder[s] = Wasm.pg_step_current(s);
    trace.flags[s] = Wasm.pg_step_flags(s);
  }
  const pathLen = Wasm.pg_final_path_len();
  if (pathLen === SENTINEL_NONE) {
    trace.reachable = false;
    trace.finalPath = null;
  } else {
    trace.reachable = true;
    trace.finalPath = new Array(pathLen);
    for (let i = 0; i < pathLen; i++) {
      trace.finalPath[i] = Wasm.pg_final_path_at(i);
    }
  }

  // 重置动画：自动从头播放新轨迹。
  anim.frame = 0;
  anim.accumulator = 0;
  anim.playing = true;
  updateButtons();
  updateProgressHud();
}

/** 取最近一次 wasm 操作的错误码并转为中文描述。 */
function describeError() {
  const code = Wasm.pg_last_error ? Wasm.pg_last_error() : 5;
  return (ERROR_MESSAGES[code] || "未知错误") + "（码 " + code + "）";
}

// ============================ 网格编辑（同步 wasm） ============================

/** 把 JS 镜像整体重置为一个 rows×cols 全通行网格，并同步 wasm。 */
function resetGrid(rows, cols) {
  const code = Wasm.pg_reset(rows, cols);
  if (code !== 0) {
    setStatus("重置失败：" + describeError(), true);
    return false;
  }
  model.rows = rows;
  model.cols = cols;
  model.blocked = new Set();
  model.start = 0;
  model.goal = rows * cols - 1;
  // 同步当前算法选择到新会话。
  Wasm.pg_select_algo(model.algo);
  layoutCanvas();
  recompute();
  setStatus("");
  return true;
}

/** 尝试把起点移动到 cell；非法则拒绝并闪烁反馈。 */
function trySetStart(cell) {
  if (cell === model.start) return;
  const code = Wasm.pg_set_start(cell);
  if (code === 0) {
    model.start = cell;
    recompute();
    setStatus("");
  } else {
    flashReject(cell);
    setStatus("起点放置被拒绝：" + describeError(), true);
  }
}

/** 尝试把终点移动到 cell；非法则拒绝并闪烁反馈。 */
function trySetGoal(cell) {
  if (cell === model.goal) return;
  const code = Wasm.pg_set_goal(cell);
  if (code === 0) {
    model.goal = cell;
    recompute();
    setStatus("");
  } else {
    flashReject(cell);
    setStatus("终点放置被拒绝：" + describeError(), true);
  }
}

/** 把 cell 的障碍状态设为 desired（true=障碍）；非法则拒绝并闪烁反馈。 */
function trySetObstacle(cell, desired) {
  const already = model.blocked.has(cell);
  if (already === desired) return; // 幂等，无需操作
  const code = Wasm.pg_set_obstacle(cell, desired ? 1 : 0);
  if (code === 0) {
    if (desired) {
      model.blocked.add(cell);
    } else {
      model.blocked.delete(cell);
    }
    recompute();
    setStatus("");
  } else {
    flashReject(cell);
    setStatus("障碍切换被拒绝：" + describeError(), true);
  }
}

/** 清除所有障碍（逐格还原，wasm 同步）。 */
function clearObstacles() {
  const cells = Array.from(model.blocked);
  for (const cell of cells) {
    Wasm.pg_set_obstacle(cell, 0);
  }
  model.blocked.clear();
  recompute();
  setStatus("");
}

// ============================ 指针交互 ============================

/** 将鼠标/触摸事件坐标换算为网格线性下标；越界返回 -1。 */
function eventToCell(evt) {
  const rect = canvas.getBoundingClientRect();
  // 画布可能被 CSS 缩放：用 width/height 与渲染分辨率换算。
  const scaleX = canvas.width / rect.width;
  const scaleY = canvas.height / rect.height;
  const px = (evt.clientX - rect.left) * scaleX;
  const py = (evt.clientY - rect.top) * scaleY;
  const col = Math.floor(px / cellSize);
  const row = Math.floor(py / cellSize);
  if (row < 0 || row >= model.rows || col < 0 || col >= model.cols) {
    return -1;
  }
  return row * model.cols + col;
}

function onPointerDown(evt) {
  evt.preventDefault();
  const cell = eventToCell(evt);
  if (cell < 0) return;
  if (cell === model.start) {
    interaction.mode = "start";
  } else if (cell === model.goal) {
    interaction.mode = "goal";
  } else {
    // 在空白/障碍格上：进入绘制模式，目标状态取「当前状态取反」（切换）。
    interaction.mode = "paint";
    interaction.paintValue = !model.blocked.has(cell);
    trySetObstacle(cell, interaction.paintValue);
  }
  canvas.setPointerCapture && canvas.setPointerCapture(evt.pointerId);
}

function onPointerMove(evt) {
  if (!interaction.mode) return;
  evt.preventDefault();
  const cell = eventToCell(evt);
  if (cell < 0) return;
  if (interaction.mode === "start") {
    trySetStart(cell);
  } else if (interaction.mode === "goal") {
    trySetGoal(cell);
  } else if (interaction.mode === "paint") {
    // 拖动绘制：对途经的非端点格统一施加 paintValue。
    if (cell !== model.start && cell !== model.goal) {
      trySetObstacle(cell, interaction.paintValue);
    }
  }
}

function onPointerUp(evt) {
  if (!interaction.mode) return;
  evt.preventDefault();
  interaction.mode = null;
  interaction.paintValue = null;
  try {
    if (canvas.releasePointerCapture && evt.pointerId != null) {
      canvas.releasePointerCapture(evt.pointerId);
    }
  } catch (_e) {
    // 指针未被捕获时 releasePointerCapture 会抛出，忽略即可。
  }
}

// ============================ 动画 + 帧率 ============================

/** 主循环：每个 rAF tick 测量帧率、按速推进动画、渲染、刷新 HUD。 */
function tick(ts) {
  // --- 帧率测量：滚动 1 秒窗口（Requirement 3.5）---
  fpsMeter.timestamps.push(ts);
  const windowStart = ts - 1000;
  while (
    fpsMeter.timestamps.length > 0 &&
    fpsMeter.timestamps[0] < windowStart
  ) {
    fpsMeter.timestamps.shift();
  }
  // 窗口内帧数即为最近 1 秒的实测 fps。
  fpsMeter.currentFps = fpsMeter.timestamps.length;

  // --- 动画推进（按 stepsPerSecond 控速）---
  if (anim.playing && trace.stepCount > 0) {
    if (anim.lastAdvanceTs === 0) anim.lastAdvanceTs = ts;
    const dt = (ts - anim.lastAdvanceTs) / 1000;
    anim.lastAdvanceTs = ts;
    anim.accumulator += dt * anim.stepsPerSecond;
    if (anim.accumulator >= 1) {
      const advance = Math.floor(anim.accumulator);
      anim.accumulator -= advance;
      anim.frame = Math.min(anim.frame + advance, trace.stepCount);
      if (anim.frame >= trace.stepCount) {
        anim.playing = false;
        updateButtons();
      }
      updateProgressHud();
    }
  } else {
    anim.lastAdvanceTs = ts;
  }

  // --- 渲染 ---
  render();

  // --- HUD 每 500ms 刷新一次（Requirement 3.5）---
  if (ts - fpsMeter.lastHudUpdate >= 500) {
    fpsMeter.lastHudUpdate = ts;
    updateFpsHud();
  }

  requestAnimationFrame(tick);
}

/** 刷新帧率显示与 <60fps 警告（Requirement 3.5 / 3.6）。 */
function updateFpsHud() {
  hudFps.textContent = String(fpsMeter.currentFps);
  hudSize.textContent = model.rows + " × " + model.cols;
  hudAlgo.textContent = ALGO_NAMES[model.algo] || "—";
  // 仅在有帧样本时判定（避免页面初始未渲染就误报）。
  const below = fpsMeter.timestamps.length > 0 && fpsMeter.currentFps < TARGET_FPS;
  hudWarning.hidden = !below;
}

/** 刷新进度 / 状态显示。 */
function updateProgressHud() {
  hudProgress.textContent = anim.frame + " / " + trace.stepCount;
  let state;
  if (trace.stepCount === 0) {
    state = "就绪";
  } else if (anim.frame < trace.stepCount) {
    state = anim.playing ? "播放中" : "已暂停";
  } else if (trace.reachable) {
    state = "已完成 · 找到路径（长度 " +
      (trace.finalPath ? trace.finalPath.length : 0) + "）";
  } else {
    state = "已完成 · 目标不可达";
  }
  hudState.textContent = state;
}

// ============================ 控件 ============================

/** 依据动画状态启用/禁用播放控件。 */
function updateButtons() {
  const hasTrace = trace.stepCount > 0;
  playBtn.disabled = !hasTrace || anim.playing || anim.frame >= trace.stepCount;
  pauseBtn.disabled = !hasTrace || !anim.playing;
  stepBtn.disabled = !hasTrace || anim.frame >= trace.stepCount;
  restartBtn.disabled = !hasTrace;
}

function bindControls() {
  algoSelect.addEventListener("change", () => {
    const code = parseInt(algoSelect.value, 10);
    const rc = Wasm.pg_select_algo(code);
    if (rc === 0) {
      model.algo = code;
      recompute();
    } else {
      setStatus("算法选择失败：" + describeError(), true);
    }
  });

  resetBtn.addEventListener("click", () => {
    const rows = clampInt(rowsInput.value, 2, 120, model.rows);
    const cols = clampInt(colsInput.value, 2, 120, model.cols);
    rowsInput.value = rows;
    colsInput.value = cols;
    resetGrid(rows, cols);
  });

  clearObstaclesBtn.addEventListener("click", clearObstacles);

  playBtn.addEventListener("click", () => {
    if (anim.frame >= trace.stepCount) anim.frame = 0;
    anim.playing = true;
    anim.lastAdvanceTs = 0;
    updateButtons();
    updateProgressHud();
  });

  pauseBtn.addEventListener("click", () => {
    anim.playing = false;
    updateButtons();
    updateProgressHud();
  });

  stepBtn.addEventListener("click", () => {
    anim.playing = false;
    if (anim.frame < trace.stepCount) {
      anim.frame += 1;
    }
    updateButtons();
    updateProgressHud();
  });

  restartBtn.addEventListener("click", () => {
    anim.frame = 0;
    anim.accumulator = 0;
    anim.playing = true;
    anim.lastAdvanceTs = 0;
    updateButtons();
    updateProgressHud();
  });

  speedInput.addEventListener("input", () => {
    anim.stepsPerSecond = clampInt(speedInput.value, 1, 600, 120);
    speedValue.textContent = String(anim.stepsPerSecond);
  });

  // 指针事件（统一鼠标 / 触摸）。
  canvas.addEventListener("pointerdown", onPointerDown);
  canvas.addEventListener("pointermove", onPointerMove);
  canvas.addEventListener("pointerup", onPointerUp);
  canvas.addEventListener("pointercancel", onPointerUp);
  canvas.addEventListener("pointerleave", (e) => {
    // 离开画布时结束「绘制」模式，但拖拽端点保持（已用 setPointerCapture）。
    if (interaction.mode === "paint") onPointerUp(e);
  });

  // 窗口缩放时重排画布。
  window.addEventListener("resize", () => {
    layoutCanvas();
  });
}

/** 解析整数并夹取到 [min,max]，非法时回退到 fallback。 */
function clampInt(value, min, max, fallback) {
  const n = parseInt(value, 10);
  if (Number.isNaN(n)) return fallback;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

// ============================ 初始化 ============================

function cacheDom() {
  canvas = document.getElementById("grid-canvas");
  ctx = canvas.getContext("2d");
  algoSelect = document.getElementById("algo-select");
  rowsInput = document.getElementById("rows-input");
  colsInput = document.getElementById("cols-input");
  resetBtn = document.getElementById("reset-btn");
  playBtn = document.getElementById("play-btn");
  pauseBtn = document.getElementById("pause-btn");
  stepBtn = document.getElementById("step-btn");
  restartBtn = document.getElementById("restart-btn");
  clearObstaclesBtn = document.getElementById("clear-obstacles-btn");
  speedInput = document.getElementById("speed-input");
  speedValue = document.getElementById("speed-value");
  hudFps = document.getElementById("hud-fps");
  hudSize = document.getElementById("hud-size");
  hudAlgo = document.getElementById("hud-algo");
  hudProgress = document.getElementById("hud-progress");
  hudState = document.getElementById("hud-state");
  hudWarning = document.getElementById("hud-fps-warning");
  statusLine = document.getElementById("status-line");
  engineState = document.getElementById("engine-state");
}

/** 在 wasm 不可用时禁用交互并提示（仍保持页面同源、无外部请求）。 */
function disableInteraction(message) {
  setStatus(message, true);
  [
    algoSelect,
    rowsInput,
    colsInput,
    resetBtn,
    playBtn,
    pauseBtn,
    stepBtn,
    restartBtn,
    clearObstaclesBtn,
    speedInput,
  ].forEach((el) => {
    if (el) el.disabled = true;
  });
}

async function main() {
  cacheDom();
  anim.stepsPerSecond = clampInt(speedInput.value, 1, 600, 120);
  speedValue.textContent = String(anim.stepsPerSecond);

  // 先把画布按默认网格排好版并渲染一帧空网格，提供即时视觉反馈。
  layoutCanvas();
  render();

  try {
    await loadWasm();
    engineState.textContent = "引擎就绪 · wasm 已加载";
  } catch (e) {
    engineState.textContent = "引擎加载失败";
    disableInteraction(
      "无法加载 WASM 引擎：" +
        (e && e.message ? e.message : String(e)) +
        "。请确认 playground.wasm 已与本页同源部署。"
    );
    // 仍启动渲染循环以显示空网格与提示。
    requestAnimationFrame(tick);
    return;
  }

  // 初始化会话：重置为默认网格、选择默认算法、计算首条轨迹。
  bindControls();
  algoSelect.value = String(model.algo);
  resetGrid(model.rows, model.cols);

  // 启动主循环（持续测量帧率 + 播放动画）。
  requestAnimationFrame(tick);
}

// DOMContentLoaded 后启动（脚本以 defer 加载，DOM 已就绪时直接运行）。
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", main);
} else {
  main();
}
