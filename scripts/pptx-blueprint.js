// ================================================================
// PPTX Blueprint v1.0 — TRIO 3.0 标准化 PPTX 生成模板
// ================================================================
// 使用说明：
//   1. 所有新 PPTX 脚本从此模板派生
//   2. 中文必须用 FONT.zh / FONT.zhBold，英文用 FONT.en / FONT.enBold
//   3. 绝对禁止直接写 "Arial" 作为中文 fontFace
//   4. 违者 check-cjk-fonts.py 会在生成后拦截
// ================================================================

const pptxgen = require("pptxgenjs");

// === 字体常量（锁定，不可覆盖） ===
// 用 Object.freeze 防止运行时被意外修改
const FONT = Object.freeze({
  zh:       "Microsoft YaHei",        // 中文正文 — 永远不要改成 Arial
  zhBold:   "Microsoft YaHei Bold",   // 中文标题
  en:       "Segoe UI",               // 英文/数字正文
  enBold:   "Segoe UI Bold",          // 英文/数字标题
  mono:     "Cascadia Code",          // 等宽/代码
});

// 运行时断言：如果检测到 FONT 被修改，立即报错
function assertFontNotLatin(fontName, context) {
  const forbidden = ["Arial", "Calibri", "Helvetica", "Times New Roman", "Cambria"];
  for (const bad of forbidden) {
    if (fontName.toLowerCase().includes(bad.toLowerCase())) {
      throw new Error(
        `[CJK-FONT-ERROR] ${context}: 检测到拉丁字体 "${fontName}" 被用于中文文本。\n` +
        `请使用 FONT.zh 或 FONT.zhBold 代替。\n` +
        `错误位置: ${context}`
      );
    }
  }
}

// === 色彩预设 — 科技深色风 ===
const COLOR_DARK = Object.freeze({
  space:    "080C1A",
  navy:     "0F1832",
  cardBg:   "141E3A",
  cyan:     "00D4FF",
  purple:   "7B5CFC",
  orange:   "FF6B35",
  green:    "00E5A0",
  coral:    "FF3B5C",
  white:    "FFFFFF",
  gray50:   "E8ECF4",
  gray300:  "8E94A5",
  gray500:  "5A6072",
  gray700:  "2D3345",
});

// === 色彩预设 — 企业咨询风（罗欣/麦肯锡式） ===
// 用法: const COLOR = COLOR_CONSULTING; (覆盖默认 COLOR_DARK)
const COLOR_CONSULTING = Object.freeze({
  navy:     "1B3A5C",   // 主色 — 封面侧栏、卡片头、分区背景
  copper:   "C8956C",   // 唯一点缀 — 标题竖线(0.1"×0.4")、封面装饰
  warmBg:   "E8E2DA",   // 强调底 — CEO引用框、关键词标签、底部提示条
  slate:    "7A8B9E",   // 辅助文 — 副标题、标签、页码
  charcoal: "2A2A2A",   // 正文
  green:    "5B9A5E",   // 阳性指标
  white:    "FFFFFF",
  medBlue:  "2A4F7A",   // 中蓝变体
});

// === 默认色彩（向后兼容）===
const COLOR = COLOR_DARK;

// === 排版预设 — 企业咨询风 ===
const LAYOUT_CONSULTING = Object.freeze({
  slideW: 17.8,           // 英寸 (16:9 宽屏)
  slideH: 10.0,
  marginLeft: 0.8,        // 统一左边距
  contentW: 16.1,         // 内容区宽
  cardStdW: 3.5,          // 标准卡片宽
  cardWideW: 4.4,         // 宽卡片宽 (4列布局第4列)
  cardGap: 0.4,           // 卡片间距
  titleY: 0.65,           // 标题 y 坐标
  accentBarW: 0.1,        // 暖铜竖线宽
  accentBarH: 0.4,        // 暖铜竖线高
  fontSize: {
    mega: 240,            // 分区页装饰数字
    coverTitle: 42,       // 封面标题
    sectionTitle: 36,     // 分区标题
    pageTitle: 28,        // 内容页标题
    cardTitle: 22,        // 卡片内标题
    body: 16,             // 正文
    small: 14,            // 标签/注释
    tiny: 12,             // 底部提示
  },
});

// === 工具函数 ===

// 创建章节封面页
function addChapterPage(slide, pres, partNum, title, subtitle) {
  slide.background = { color: COLOR.space };
  slide.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 10, h: 0.03, fill: { color: COLOR.cyan } });
  slide.addShape(pres.shapes.RECTANGLE, { x: 7.2, y: 0, w: 2.8, h: 5.625, fill: { color: COLOR.navy, transparency: 40 } });
  slide.addText(`PART ${partNum}`, {
    x: 0.8, y: 1.3, w: 8.4, h: 0.5,
    fontSize: 14, fontFace: FONT.en, color: COLOR.orange, charSpacing: 8, margin: 0,
  });
  assertFontNotLatin(FONT.en, `章节页 PART ${partNum}`);
  slide.addText(title, {
    x: 0.8, y: 1.8, w: 8.4, h: 1.0,
    fontSize: 44, fontFace: FONT.zhBold, color: COLOR.white, margin: 0,
  });
  assertFontNotLatin(FONT.zhBold, `章节页标题 ${title}`);
  slide.addText(subtitle, {
    x: 0.8, y: 2.85, w: 8.4, h: 0.5,
    fontSize: 13, fontFace: FONT.zh, color: COLOR.gray300, margin: 0,
  });
  slide.addShape(pres.shapes.LINE, { x: 0.8, y: 3.5, w: 2.5, h: 0, line: { color: COLOR.orange, width: 3 } });
  slide.addShape(pres.shapes.RECTANGLE, { x: 0.8, y: 4.9, w: 3.0, h: 0.02, fill: { color: COLOR.purple } });
}

// 创建内容页标题
function addPageTitle(slide, pres, title, subtitle) {
  slide.background = { color: COLOR.white };
  slide.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 10, h: 0.03, fill: { color: COLOR.cyan } });
  slide.addText(title, {
    x: 0.6, y: 0.3, w: 8.8, h: 0.55,
    fontSize: 24, fontFace: FONT.zhBold, color: COLOR.navy, margin: 0,
  });
  assertFontNotLatin(FONT.zhBold, `页面标题 ${title}`);
  if (subtitle) {
    slide.addText(subtitle, {
      x: 0.6, y: 0.85, w: 8.8, h: 0.3,
      fontSize: 11, fontFace: FONT.en, color: COLOR.gray500, margin: 0,
    });
  }
  slide.addShape(pres.shapes.LINE, { x: 0.6, y: 1.2, w: 2.0, h: 0, line: { color: COLOR.cyan, width: 2.5 } });
}

// 创建页脚
function addFooter(slide, pageNum) {
  slide.addText(`CRX · CeramX  |  企业文件  |  机密  |  ${pageNum}`, {
    x: 0.4, y: 5.2, w: 9.2, h: 0.3,
    fontSize: 7, fontFace: FONT.en, color: COLOR.gray300, align: "right", margin: 0,
  });
}

// 关键指标卡片 (dashboard 风格)
function addMetricCard(slide, x, y, w, h, value, label, accentColor) {
  slide.addShape(pres.shapes.RECTANGLE, { x: x, y: y, w: w, h: h, fill: { color: COLOR.cardBg }, shadow: { type: "outer", blur: 6, offset: 2, angle: 135, color: "000000", opacity: 0.25 } });
  slide.addShape(pres.shapes.RECTANGLE, { x: x, y: y, w: w, h: 0.04, fill: { color: accentColor } });
  slide.addText(value, {
    x: x + 0.15, y: y + 0.2, w: w - 0.3, h: h * 0.5,
    fontSize: 26, fontFace: FONT.enBold, color: accentColor, align: "center", margin: 0,
  });
  slide.addText(label, {
    x: x + 0.15, y: y + h * 0.55, w: w - 0.3, h: h * 0.35,
    fontSize: 10, fontFace: FONT.zh, color: COLOR.gray300, align: "center", margin: 0,
  });
}

// ================================================================
// 企业咨询风辅助函数（COPY 罗欣方案）
// 使用前先: const C = COLOR_CONSULTING; const L = LAYOUT_CONSULTING;
// ================================================================

// 封面页 — 深蓝侧栏 + 右侧暖米色标签组
function addConsultingCover(slide, pres, title, subtitle, meta, tags) {
  const C = COLOR_CONSULTING;
  // 左侧深蓝色块
  slide.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 11.1, h: 10.0, fill: { color: C.navy } });
  // 铜色装饰线
  slide.addShape(pres.shapes.RECTANGLE, { x: 0.8, y: 2.8, w: 1.1, h: 0.03, fill: { color: C.copper } });
  // 标题
  slide.addText(title, {
    x: 0.8, y: 3.1, w: 9.2, h: 0.8, fontSize: 42, fontFace: FONT.zhBold, color: C.white, margin: 0,
  });
  slide.addText(subtitle, {
    x: 0.8, y: 4.2, w: 7.8, h: 0.5, fontSize: 16, fontFace: FONT.zh, color: C.slate, margin: 0,
  });
  slide.addText(meta, {
    x: 0.8, y: 8.9, w: 6.7, h: 0.3, fontSize: 14, fontFace: FONT.zh, color: C.slate, margin: 0,
  });
  // 右侧标签组 — 暖米色方块
  if (tags && tags.length) {
    tags.forEach((tag, i) => {
      const col = i % 2, row = Math.floor(i / 2);
      const tx = 11.5 + col * 3.0, ty = 2.5 + row * 1.8;
      slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
        x: tx, y: ty, w: 2.3, h: 0.7, fill: { color: C.warmBg }, rectRadius: 0.05,
      });
      slide.addText(tag, {
        x: tx, y: ty, w: 2.3, h: 0.7, fontSize: 16, fontFace: FONT.zh, color: C.charcoal,
        align: "center", valign: "middle", margin: 0,
      });
    });
  }
}

// 分区过渡页 — 全深蓝底 + 超大数字 + 标题
function addConsultingSection(slide, pres, num, title) {
  const C = COLOR_CONSULTING;
  slide.background = { color: C.navy };
  slide.addText(num, {
    x: 0.8, y: 1.0, w: 16, h: 4.0, fontSize: 240, fontFace: FONT.enBold, color: C.white,
    align: "center", valign: "middle", margin: 0, transparency: 70,
  });
  slide.addText(title, {
    x: 0.8, y: 5.5, w: 16, h: 1.2, fontSize: 36, fontFace: FONT.zhBold, color: C.white,
    align: "center", valign: "middle", margin: 0,
  });
}

// 标准内容页 — 暖铜竖线 + 标题
function addConsultingTitle(slide, pres, title) {
  const C = COLOR_CONSULTING;
  slide.addShape(pres.shapes.RECTANGLE, {
    x: 0.8, y: 0.7, w: 0.1, h: 0.4, fill: { color: C.copper },
  });
  slide.addText(title, {
    x: 1.1, y: 0.6, w: 15.6, h: 0.6, fontSize: 28, fontFace: FONT.zhBold, color: C.navy, margin: 0,
  });
}

// 白色卡片 — 企业咨询风的核心内容容器
function addConsultingCard(slide, pres, x, y, w, h, header, bodyLines) {
  const C = COLOR_CONSULTING;
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h, fill: { color: C.white }, rectRadius: 0.05,
  });
  slide.addText(header, {
    x: x + 0.2, y: y + 0.15, w: w - 0.4, h: 0.35, fontSize: 18, fontFace: FONT.zhBold, color: C.navy, margin: 0,
  });
  slide.addText(bodyLines.join("\n"), {
    x: x + 0.2, y: y + 0.55, w: w - 0.4, h: h - 0.7, fontSize: 14, fontFace: FONT.zh, color: C.charcoal,
    lineSpacingMultiple: 1.3, margin: 0,
  });
}

// 暖米色强调块 — CEO引用/底部提示/关键信息
function addConsultingCallout(slide, pres, x, y, w, h, text, fontSize) {
  const C = COLOR_CONSULTING;
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h, fill: { color: C.warmBg }, rectRadius: 0.05,
  });
  slide.addText(text, {
    x: x + 0.3, y: y + 0.15, w: w - 0.6, h: h - 0.3, fontSize: fontSize || 14,
    fontFace: FONT.zh, color: C.charcoal, lineSpacingMultiple: 1.3, margin: 0,
  });
}

// 导出（配合 require 使用）
module.exports = {
  FONT,
  COLOR,
  COLOR_DARK,
  COLOR_CONSULTING,
  LAYOUT_CONSULTING,
  assertFontNotLatin,
  addChapterPage,
  addPageTitle,
  addFooter,
  addMetricCard,
  addConsultingCover,
  addConsultingSection,
  addConsultingTitle,
  addConsultingCard,
  addConsultingCallout,
  pptxgen,
};
