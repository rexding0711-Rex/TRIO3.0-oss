# TRIO 3.0 前端生成规则

> 基于 K3 逆向工程提取的 10 条设计决策 · 2026-07-19
> 工具库: `trio-fe-kit.js`

---

## 生成 HTML 前的硬流程

**不是门禁——是基础。** 像 K3 的 22 个图表基于 `window.U` 一样，TRIO 生成的页面基于 `window.TK`。

### 1. 引入工具库
```html
<script src="trio-fe-kit.js"></script>
<!-- 或者内联 trio-fe-kit.js 的内容到 <script> 标签中 -->
```

### 2. 根据页面类型，强制使用以下 TK 模块

| 页面类型 | 必须使用 | 禁止 |
|---------|---------|------|
| 含 Canvas 图表 | `TK.bindCanvas()` | 裸写 `canvas.getContext("2d")` 不处理 DPR |
| 含数据图表 | `TK.frameChart()` + `TK.PAL` | 自建 title/sub/src HTML 模板 |
| 含可调参数 | `TK.paramSystem()` | 手动绑定 slider → localStorage |
| 含滚动章节 | `TK.observeSections()` | `window.addEventListener("scroll", ...)` |
| 含数字动画 | `TK.countUp()` | 手写 RAF 循环 |
| 含数据声明 | `TK.fmtSrc()` + 来源数组 | 无来源标注的数据展示 |

### 3. CSS 变量——按角色命名，不按颜色
```css
:root {
  --surface: #...     /* 不是 --bg-white */
  --text-primary: #... /* 不是 --text-dark */
  --accent: #...       /* 不是 --blue-500 */
  --negative: #...     /* 不是 --red */
}
```

### 4. Canvas 图表——每个图表一个 IIFE，共享 TK
```javascript
// chart-xxx.js
(() => {
  const host = document.getElementById("my-chart");
  if (!host) return;                         // ← 防御入口
  
  const body = TK.frameChart(host, {
    title: "图表标题",
    sub: "副标题说明",
    src: ["company", "broker"],              // ← 来源分类
  });
  
  const { fit, ctx } = TK.bindCanvas(canvas);
  // ... 绘制逻辑
})();
```

### 5. 数据——每条声明带来源
```javascript
const data = {
  value: 412.9,
  unit: "US$ billions",
  source: ["company", "broker"],  // 公司披露 + 券商研究
  note: "四大CSP FY2025 资本开支合计",
};
```

---

## 检查清单（DeepSeek 审计用）

- [ ] Canvas 是否通过 `TK.bindCanvas()` 初始化？（HiDPI）
- [ ] 调色板是否使用 `TK.PAL` 而非硬编码 hex？
- [ ] 图表外框是否使用 `TK.frameChart()` 而非手写 HTML？
- [ ] 滚动编排是否用 `TK.observeSections()` 而非 scroll 事件？
- [ ] 数字动画是否用 `TK.countUp()` 并保存了 cleanup 函数？
- [ ] 数据声明是否带 `source` 字段？
- [ ] CSS 变量名是否按角色（--surface / --text-primary）而非颜色（--white / --dark）命名？
- [ ] 每个图表模块是否是独立 IIFE，通过 TK 通信？
