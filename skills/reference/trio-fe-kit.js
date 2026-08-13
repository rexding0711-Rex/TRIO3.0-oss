/**
 * TRIO Frontend Kit v1.0
 * 基于 K3 前端决策系统提取——10 条设计原则编码为可复用工具
 *
 * 用法: Claude Code 生成 HTML 时内联此文件
 *       <script src="trio-fe-kit.js"></script>
 *       或直接内联到 <script> 标签中
 *
 * 设计原则（对应 K3 决策 #1-#10）:
 *   #1  共享工具内核——所有模块通过 window.TK 通信
 *   #2  数据层即分析层——数据版本化 + 来源标注
 *   #3  单 Canvas 管线——一个 Canvas 一个 RAF 循环
 *   #4  Token 名 = 角色——CSS 变量说"纸/墨"，不说"白/蓝"
 *   #5  Schema 即 UI——配置一次，DOM/状态/持久化自动派生
 *   #6  (3D 相机——本 Kit 不覆盖，3D 场景用 Three.js + Catmull-Rom)
 *   #7  IIFE 自包含——每个模块独立，通过 TK 通信
 *   #8  IO 驱动编排——IntersectionObserver，不监听 scroll
 *   #9  每条声明可溯源——数据带 source 字段
 *   #10 受限调色板——颜色有语义角色，不是任意选择
 */

window.TK = (() => {
  "use strict";

  // ══════════════════════════════════════════════
  // 数学基元
  // ══════════════════════════════════════════════
  const TAU = Math.PI * 2;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const smooth = t => t * t * (3 - 2 * t);                    // smoothstep
  const ease = (cur, tgt, dt, dur) =>                        // 指数衰减平滑
    cur + (tgt - cur) * (1 - Math.exp(-dt / dur));
  const easeInOut = t =>                                      // 缓入缓出
    t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

  // 确定性 RNG (squirrel3 变体——可复现随机)
  function makeRng(seed) {
    let s = seed >>> 0;
    return () => {
      s += 0x6d2b79f5; let t = s;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // ══════════════════════════════════════════════
  // 受限调色板（决策 #10）
  // 颜色按语义角色定义——不是按色相命名
  // ══════════════════════════════════════════════
  const PAL = {
    // 墨层——主图表色系（"One chart, one family"）
    ink:    "#051c2c",
    inkMd:  "#42566a",
    inkLo:  "#8595a6",
    paper:  "#ffffff",
    line:   "#dbe2ea",

    // 强调色——电光蓝家族
    accent:   "#2251ff",
    accentHi: "#1233b8",
    accentLo: "#7d9bff",

    // 语义色——每个只用于一种信息类型
    neg:    "#c22f4e",  // 只用于负面：下跌/缺口/缺失
    pos:    "#008a6d",  // 只用于正面：增长/盈利

    // 来源徽章——这四个永远不准出现在图表数据着色中
    source: {
      company:   "#7a45c9",  // 公司披露
      broker:    "#b07a10",  // 券商研究
      industry:  "#008a6d",  // 行业/官方
      research:  "#2251ff",  // 自主研究
    }
  };

  // ══════════════════════════════════════════════
  // 字体桥接——CSS 变量 → Canvas 字体（决策 #4）
  // ══════════════════════════════════════════════
  function getFonts() {
    const cs = getComputedStyle(document.documentElement);
    return {
      sans:  cs.getPropertyValue("--font-sans").trim()  || 'system-ui, sans-serif',
      mono:  cs.getPropertyValue("--font-mono").trim()  || 'monospace',
      serif: cs.getPropertyValue("--font-serif").trim() || 'Georgia, serif',
    };
  }
  const FONTS = (() => {
    try { return getFonts(); } catch { return { sans: 'sans-serif', mono: 'monospace', serif: 'serif' }; }
  })();
  function font(px, weight, fam) {
    // 如果 TK 在 DOM 之前初始化，延迟读取
    const f = (fam && FONTS[fam]) ? FONTS[fam] : (FONTS.sans || 'sans-serif');
    return (weight ? weight + " " : "") + px + "px " + f;
  }

  // ══════════════════════════════════════════════
  // HiDPI Canvas 绑定（决策 #3）
  // ══════════════════════════════════════════════
  function bindCanvas(canvas) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const ctx = canvas.getContext("2d");
    function fit() {
      const r = canvas.getBoundingClientRect();
      canvas.width  = Math.round(r.width  * dpr);
      canvas.height = Math.round(r.height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      return { w: r.width, h: r.height, cx: r.width / 2, cy: r.height / 2 };
    }
    return { fit, ctx, dpr };
  }

  // ══════════════════════════════════════════════
  // 图表外框——统一标题/副标题/来源（决策 #7）
  // ══════════════════════════════════════════════
  function frameChart(host, { title, sub, src }) {
    const wrap = document.createElement("div");
    wrap.className = "tk-chart";

    if (title) {
      const h = document.createElement("div");
      h.className = "tk-chart-title";
      h.textContent = title;
      wrap.appendChild(h);
    }
    if (sub) {
      const s = document.createElement("div");
      s.className = "tk-chart-sub";
      s.textContent = sub;
      wrap.appendChild(s);
    }

    const body = document.createElement("div");
    body.className = "tk-chart-body";
    wrap.appendChild(body);

    if (src) {
      const s = document.createElement("div");
      s.className = "tk-chart-src";
      s.textContent = typeof src === "string" ? "来源：" + src : fmtSrc(src);
      wrap.appendChild(s);
    }

    host.appendChild(wrap);
    return body;
  }

  // ══════════════════════════════════════════════
  // 数字滚动动画——返回 cleanup 函数
  // ══════════════════════════════════════════════
  function countUp(el, opts = {}) {
    const { from = 0, to = 1, dur = 1100, fmt = v => Math.round(v).toLocaleString("en-US") } = opts;
    let raf = 0, t0 = null;
    const tick = ts => {
      if (t0 == null) t0 = ts;
      const t = clamp((ts - t0) / dur, 0, 1);
      const e = 1 - Math.pow(1 - t, 3);  // ease-out cubic
      el.textContent = fmt(lerp(from, to, e));
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);  // ← cleanup
  }

  // ══════════════════════════════════════════════
  // 来源格式化（决策 #9）
  // ══════════════════════════════════════════════
  const SOURCE_LABELS = {
    company:  "公司披露",
    broker:   "券商研究",
    industry: "行业/官方",
    research: "自主研究",
  };
  function fmtSrc(src) {
    if (typeof src === "string") return "来源：" + src;
    if (Array.isArray(src)) return "来源：" + src.map(s => SOURCE_LABELS[s] || s).join(" · ");
    return "来源：" + (SOURCE_LABELS[src] || src);
  }

  // ══════════════════════════════════════════════
  // IntersectionObserver 编排（决策 #8）
  // 替代 window.scroll——驱动章节切换
  // ══════════════════════════════════════════════
  function observeSections(sections, onActivate, opts = {}) {
    const margin = opts.rootMargin || "-38% 0px -38% 0px";
    let active = null;
    const observer = new IntersectionObserver(entries => {
      entries.forEach(en => {
        if (en.isIntersecting) {
          active = en.target.dataset.win || en.target.id;
          sections.forEach(s => s.classList.remove("active-step"));
          en.target.classList.add("active-step");
          if (onActivate) onActivate(active, en.target);
        }
      });
    }, { rootMargin: margin });
    sections.forEach(s => observer.observe(s));
    return { observer, getActive: () => active };
  }

  // 滚动关联的 UI 渐变——基于封面滚出视口的进度
  function scrollReveal(coverEl, targetEl, opts = {}) {
    const clamp01 = v => Math.min(1, Math.max(0, v));
    const upd = () => {
      const vh = window.innerHeight;
      const b = coverEl.getBoundingClientRect().bottom;
      const p = clamp01((vh * 0.8 - b) / (vh * 0.5));
      const s = p * p * (3 - 2 * p);
      targetEl.style.opacity = s.toFixed(3);
      targetEl.style.visibility = s > 0 ? "visible" : "hidden";
      if (opts.onProgress) opts.onProgress(s);
    };
    window.addEventListener("scroll", upd, { passive: true });
    window.addEventListener("resize", upd);
    upd();
    return upd;
  }

  // ══════════════════════════════════════════════
  // 声明式参数系统（决策 #5）
  // Schema → DOM slider + localStorage + URL 参数
  // ══════════════════════════════════════════════
  function paramSystem(paramDefs, opts = {}) {
    const storeKey = opts.storeKey || "tk.params.v1";
    let stored = {};
    try { stored = JSON.parse(localStorage.getItem(storeKey)) || {}; } catch { stored = {}; }

    // 值解析链: URL > localStorage > default
    function get(key) {
      const p = new URLSearchParams(location.search);
      if (p.has(key)) return parseFloat(p.get(key));
      const d = paramDefs.find(x => x.key === key);
      const s = stored[key];
      return Number.isFinite(s) ? s : (d ? d.def : undefined);
    }

    function set(key, val) {
      stored[key] = val;
      try { localStorage.setItem(storeKey, JSON.stringify(stored)); } catch {}
    }

    function reset() {
      stored = {};
      try { localStorage.setItem(storeKey, JSON.stringify(stored)); } catch {}
    }

    // 从 PARAM_DEFS 自动生成 DOM 控件
    function buildUI(container, onApply) {
      paramDefs.forEach(d => {
        const row = document.createElement("div");
        row.className = "tk-param-row";
        const label = document.createElement("label");
        label.textContent = d.label;
        const inp = document.createElement("input");
        inp.type = "range";
        inp.min = d.min; inp.max = d.max; inp.step = d.step || 1;
        inp.value = get(d.key);
        const disp = document.createElement("span");
        disp.className = "tk-param-val";
        disp.textContent = d.fmt ? d.fmt(inp.value) : inp.value;

        inp.addEventListener("input", () => {
          const v = parseFloat(inp.value);
          disp.textContent = d.fmt ? d.fmt(v) : v;
          set(d.key, v);
          if (onApply) onApply(d.key, v);
        });

        row.appendChild(label);
        row.appendChild(inp);
        row.appendChild(disp);
        container.appendChild(row);
      });
    }

    return { get, set, reset, buildUI, defs: paramDefs };
  }

  // ══════════════════════════════════════════════
  // 数据防御工具
  // ══════════════════════════════════════════════
  function safeGet(obj, path, fallback) {
    try {
      return path.split(".").reduce((o, k) => o[k], obj) ?? fallback;
    } catch { return fallback; }
  }

  function debounce(fn, delay) {
    let timer;
    return function (...args) {
      clearTimeout(timer);
      timer = setTimeout(() => fn.apply(this, args), delay);
    };
  }

  // ══════════════════════════════════════════════
  // 导出
  // ══════════════════════════════════════════════
  return {
    // 数学
    TAU, clamp, lerp, smooth, ease, easeInOut, makeRng,
    // Canvas
    bindCanvas,
    // 调色板
    PAL,
    // 字体
    FONTS, font,
    // 图表
    frameChart,
    // 动效
    countUp,
    // 来源
    fmtSrc, SOURCE_LABELS,
    // 编排
    observeSections, scrollReveal,
    // 参数系统
    paramSystem,
    // 工具
    safeGet, debounce,
  };
})();
