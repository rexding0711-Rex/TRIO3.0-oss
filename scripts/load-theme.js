// 加载设计主题的辅助模块
// 用法: const theme = require('./load-theme')('consulting-light');
const path = require('path');

function loadTheme(name) {
  const themePath = path.join(__dirname, '..', 'design', 'themes', `${name}.json`);
  const theme = require(themePath);

  // 运行时校验: 确保颜色不超过 15 个
  const colorKeys = Object.keys(theme.colors);
  if (colorKeys.length > 15) {
    console.warn(`⚠️  主题 "${name}" 包含 ${colorKeys.length} 个颜色（建议 ≤15）`);
  }

  // 确保必要颜色存在
  const required = ['pageBg', 'textMain', 'textBody', 'textMuted'];
  for (const key of required) {
    if (!theme.colors[key]) {
      throw new Error(`主题 "${name}" 缺少必要颜色: ${key}`);
    }
  }

  return theme;
}

module.exports = loadTheme;
