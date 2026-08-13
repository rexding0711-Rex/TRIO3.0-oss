#!/usr/bin/env python3
"""AI 前端代码指纹检测器 v1.0
基于 K3 逆向工程 + GPT-5.6/Fable 5/DeepSeek V4 盲审交叉验证
检测 35 条指纹（22 代码指纹 + 13 缺失熵指纹）

用法: python3 ai-frontend-fingerprint.py <目标目录>
输出: AI 生成概率报告
"""

import sys, os, re, json
from pathlib import Path
from collections import Counter, defaultdict

# ══════════════════════════════════════════════
# 指纹定义
# ══════════════════════════════════════════════

FINGERPRINTS = {
    # ── CSS 指纹 (C1-C14) ──
    "C1_CSS变量覆盖": {
        "check": "css",
        "desc": "CSS 变量全覆盖，零硬编码 hex",
        "weight": 0.5,
        "ai_signal": "positive"  # 出现 = AI 信号
    },
    "C2_半透明边框": {
        "check": "css",
        "desc": "rgba() 半透明边框",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "C3_backdrop_filter": {
        "check": "css",
        "desc": "backdrop-filter: blur() 毛玻璃",
        "weight": 0.4,
        "ai_signal": "positive"
    },
    "C4_全站等宽": {
        "check": "css",
        "desc": "JetBrains Mono / 等宽字体作为正文字体",
        "weight": 0.8,  # Fable5: 几乎可以一票否决
        "ai_signal": "positive"
    },
    "C5_伪元素特效层": {
        "check": "css",
        "desc": "body:before光晕 + body:after扫描线",
        "weight": 1.0,  # 最强视觉签名
        "ai_signal": "positive"
    },
    "C6_Grid优先": {
        "check": "css",
        "desc": "主布局用 Grid 而非 Flexbox",
        "weight": 0.2,
        "ai_signal": "positive"
    },
    "C7_clamp流体": {
        "check": "css",
        "desc": "clamp() 流体排版",
        "weight": 0.2,
        "ai_signal": "positive"
    },
    "C8_自定义滚动条": {
        "check": "css",
        "desc": "::-webkit-scrollbar 自定义",
        "weight": 0.2,
        "ai_signal": "positive"
    },
    "C9_letter_spacing微调": {
        "check": "css",
        "desc": "letter-spacing 0.02em 级微调",
        "weight": 0.6,
        "ai_signal": "positive"
    },
    "C10_统一动效": {
        "check": "css",
        "desc": "transition: all 0.15s ease",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "C11_零框架依赖": {
        "check": "all",
        "desc": "不依赖 Tailwind/Bootstrap 等 CSS 框架",
        "weight": 0.5,
        "ai_signal": "positive"
    },
    "C12_短语义类名": {
        "check": "css",
        "desc": ".hd .chip .dash .deck 极短语义类名",
        "weight": 0.5,
        "ai_signal": "positive"
    },
    "C13_fixed_sticky叠加": {
        "check": "css",
        "desc": "多层 fixed/sticky 定位不冲突",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "C14_响应式_无障碍": {
        "check": "css",
        "desc": "4断点 + prefers-reduced-motion",
        "weight": 0.4,
        "ai_signal": "positive"
    },

    # ── JS 指纹 (J1-J8) ──
    "J1_中文注释": {
        "check": "js",
        "desc": "中文注释 + 语义命名",
        "weight": 0.6,
        "ai_signal": "positive"
    },
    "J2_Canvas2D自绘": {
        "check": "js",
        "desc": "Canvas 2D 直接渲染，不依赖图表库",
        "weight": 0.8,
        "ai_signal": "positive"
    },
    "J3_localStorage版本化": {
        "check": "js",
        "desc": "localStorage 持久化，key 带版本号",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "J4_URL参数驱动": {
        "check": "js",
        "desc": "URL 参数驱动 (?q=&debug&shot)",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "J5_prefers_reduced_motion_JS": {
        "check": "js",
        "desc": "JS 侧 matchMedia prefers-reduced-motion",
        "weight": 0.4,
        "ai_signal": "positive"
    },
    "J6_IntersectionObserver": {
        "check": "js",
        "desc": "IntersectionObserver 视口外暂停渲染",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "J7_确定性RNG": {
        "check": "js",
        "desc": "确定性 RNG，种子可复现",
        "weight": 0.7,
        "ai_signal": "positive"
    },
    "J8_数据层版本化": {
        "check": "js",
        "desc": "数据层版本化 (v51→v52→v53)",
        "weight": 0.9,
        "ai_signal": "positive"
    },

    # ── 缺失熵指纹 (N1-N13) — 外部大模型发现 ──
    "N1_零TODO": {
        "check": "all",
        "desc": "零 TODO/FIXME/HACK 注释 (人类项目平均每200-500行1个)",
        "weight": 1.0,
        "ai_signal": "negative"  # 缺失 = AI 信号
    },
    "N2_注释密度均匀": {
        "check": "js",
        "desc": "注释密度均匀分布，而非幂律(复杂处才注释)",
        "weight": 0.8,
        "ai_signal": "positive"
    },
    "N3_文件组织熵低": {
        "check": "structure",
        "desc": "无 utils.js/helpers.js 命名漂移，无考古层",
        "weight": 0.5,
        "ai_signal": "positive"
    },
    "N4_命名一致性过高": {
        "check": "js",
        "desc": "动词选择一致 (无 getUserById→fetchUser 漂移)",
        "weight": 0.6,
        "ai_signal": "positive"
    },
    "N5_零调试残留": {
        "check": "all",
        "desc": "零 console.log / debugger 残留",
        "weight": 0.7,
        "ai_signal": "negative"
    },
    "N6_防御性编程均匀": {
        "check": "js",
        "desc": "所有模块等密度 try-catch",
        "weight": 0.4,
        "ai_signal": "positive"
    },
    "N7_API选择过度一致": {
        "check": "js",
        "desc": "只用标准答案API (如全 async/await 不混 .then)",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "N8_魔法数字反向消失": {
        "check": "all",
        "desc": "所有数字都被提取为 CONFIG/PARAM_DEFS",
        "weight": 0.4,
        "ai_signal": "positive"
    },
    "N9_第三方洁癖": {
        "check": "all",
        "desc": "过度手写，回避 npm 生态",
        "weight": 0.5,
        "ai_signal": "positive"
    },
    "N10_教科书式覆盖顺序": {
        "check": "structure",
        "desc": "layout→typography→color→animation→responsive→a11y 固定顺序",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "N11_时间胶囊": {
        "check": "js",
        "desc": "对最新 Web API 保守使用，偏好稳定期范式",
        "weight": 0.2,
        "ai_signal": "positive"
    },
    "N12_数学一阶直译": {
        "check": "all",
        "desc": "公式直接翻译为代码，无手工性能优化痕迹",
        "weight": 0.3,
        "ai_signal": "positive"
    },
    "N13_0点15秒": {
        "check": "css",
        "desc": "transition 使用非标准 0.15s (非 Apple/Material/antd)",
        "weight": 0.2,
        "ai_signal": "positive"
    },
}

# ══════════════════════════════════════════════
# 检测器
# ══════════════════════════════════════════════

def scan_directory(root):
    """扫描目录，返回文件列表和内容"""
    files = {"css": [], "js": [], "html": [], "other": []}
    contents = {}
    for path in Path(root).rglob("*"):
        if path.is_file() and not any(p in str(path) for p in [".git", "node_modules", "vendor", ".map"]):
            ext = path.suffix.lower()
            cat = "css" if ext in [".css"] else "js" if ext in [".js", ".ts", ".jsx", ".tsx", ".glsl"] else "html" if ext in [".html"] else "other"
            files[cat].append(str(path))
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as f:
                    contents[str(path)] = f.read()
            except:
                pass
    return files, contents


def check_C1(contents):
    """CSS 变量覆盖 vs 硬编码 hex"""
    css_text = "\n".join(c for p, c in contents.items() if p.endswith(".css"))
    var_count = len(re.findall(r'var\(--', css_text))
    hex_count = len(re.findall(r'#[0-9a-fA-F]{3,6}(?![\w-]*\s*;)', css_text))
    # 有 var 声明 + hex 使用极少 = 高覆盖
    has_root = bool(re.search(r':root\s*\{', css_text))
    score = min(1.0, var_count / max(hex_count + var_count, 1) * 2) if has_root else 0
    return {"var_count": var_count, "hex_count": hex_count, "has_root": has_root, "score": score}


def check_C4(contents):
    """全站等宽字体"""
    css_text = "\n".join(c for p, c in contents.items() if p.endswith(".css"))
    mono_in_body = bool(re.search(r'body\s*\{[^}]*font-family\s*:\s*[^;]*(JetBrains\s*Mono|monospace|Menlo|Consolas)', css_text, re.DOTALL))
    has_serif_body = bool(re.search(r'body\s*\{[^}]*font-family\s*:\s*[^;]*(serif|Georgia|Songti)', css_text, re.DOTALL))
    return {"mono_in_body": mono_in_body, "has_serif_body": has_serif_body, "score": 1.0 if mono_in_body and not has_serif_body else 0.5 if mono_in_body else 0}


def check_C5(contents):
    """body:before + body:after 特效层 — 也检测 #fx scanline 等价实现"""
    css_text = "\n".join(c for p, c in contents.items() if p.endswith(".css"))
    html_text = "\n".join(c for p, c in contents.items() if p.endswith(".html"))
    has_before = bool(re.search(r'body\s*:\s*before\s*\{', css_text))
    has_after = bool(re.search(r'body\s*:\s*after\s*\{', css_text))
    has_scanline = bool(re.search(r'repeating-linear-gradient.*?(rgba\(255,255,255|transparent)', css_text, re.DOTALL))
    # GARGANTUA style: #fx overlay with scanline (equivalent pattern)
    has_fx_scanline = bool(re.search(r'#fx\s*\{[^}]*repeating-linear-gradient', css_text, re.DOTALL))
    has_fx_html = bool(re.search(r'id="fx"', html_text))
    score = 1.0 if (has_before and has_after and has_scanline) else \
            0.8 if (has_before or has_after) and has_scanline else \
            0.8 if has_fx_scanline else \
            0.6 if has_before and has_after else 0
    return {"has_before": has_before, "has_after": has_after, "has_scanline": has_scanline, "has_fx": has_fx_html, "score": score}


def check_C11(contents):
    """零 CSS 框架依赖"""
    all_text = "\n".join(contents.values())
    has_tailwind = bool(re.search(r'(tailwind|@tailwind|tailwindcss)', all_text, re.IGNORECASE))
    has_bootstrap = bool(re.search(r'(bootstrap|bootstrap\.min)', all_text, re.IGNORECASE))
    return {"has_tailwind": has_tailwind, "has_bootstrap": has_bootstrap, "score": 1.0 if (not has_tailwind and not has_bootstrap) else 0}


def check_J1(contents):
    """中文注释"""
    js_text = "\n".join(c for p, c in contents.items() if p.endswith((".js", ".ts", ".jsx", ".tsx")))
    cn_comments = len(re.findall(r'//.*[一-鿿]', js_text))
    total_lines = len(js_text.split("\n"))
    ratio = cn_comments / max(total_lines, 1)
    return {"cn_comment_count": cn_comments, "total_lines": total_lines, "ratio": ratio, "score": min(1.0, ratio * 200)}


def check_J2(contents):
    """Canvas 2D 自绘"""
    js_text = "\n".join(c for p, c in contents.items() if p.endswith((".js", ".ts")))
    has_canvas = bool(re.search(r'(getContext\(["\']2d["\']\)|canvas\.getContext)', js_text))
    has_chart_lib = bool(re.search(r'(echarts|chart\.js|d3\.js|highcharts|plotly)', js_text, re.IGNORECASE))
    return {"has_canvas_2d": has_canvas, "has_chart_lib": has_chart_lib, "score": 1.0 if (has_canvas and not has_chart_lib) else 0.5 if has_canvas else 0}


def check_J7(contents):
    """确定性 RNG"""
    js_text = "\n".join(c for p, c in contents.items() if p.endswith((".js", ".ts")))
    has_seed_rng = bool(re.search(r'(seed|makeRng|mulberry32|squirrel3|xorshift|splitmix)', js_text))
    uses_math_random = bool(re.search(r'Math\.random\(\)', js_text))
    return {"has_seed_rng": has_seed_rng, "uses_math_random": uses_math_random, "score": 1.0 if has_seed_rng else 0}


def check_J8(contents):
    """数据层版本化"""
    js_text = "\n".join(c for p, c in contents.items() if p.endswith((".js", ".ts")))
    has_version = bool(re.search(r'(data-v\d|v\d+\.js|V\d+\s*=|version.*\d+\.\d+)', js_text))
    return {"has_versioned_data": has_version, "score": 1.0 if has_version else 0}


def check_N1(contents):
    """零 TODO/FIXME"""
    all_text = "\n".join(contents.values())
    todo_count = len(re.findall(r'(TODO|FIXME|XXX|HACK)\b', all_text, re.IGNORECASE))
    total_lines = sum(len(c.split("\n")) for c in contents.values())
    density = todo_count / max(total_lines, 1)
    # 人类项目: ~1 TODO per 200-500 行
    # AI: 接近 0
    return {"todo_count": todo_count, "total_lines": total_lines, "is_zero": todo_count == 0, "score": 1.0 if todo_count == 0 else max(0, 1.0 - density * 1000)}


def check_N5(contents):
    """零调试残留"""
    all_text = "\n".join(contents.values())
    debug_count = len(re.findall(r'\b(console\.(log|warn|debug|error|dir|table)|debugger)\b', all_text))
    # 排除真正的错误处理 console.error
    error_only = len(re.findall(r'console\.error', all_text))
    clean_debug = debug_count - error_only
    return {"debug_count": clean_debug, "is_zero": clean_debug == 0, "score": 1.0 if clean_debug <= 1 else max(0, 1.0 - clean_debug * 0.1)}


def check_N3(contents):
    """文件组织熵"""
    all_files = list(contents.keys())
    # 检测命名漂移: utils.js + helpers.js 并存
    has_utils = any("utils" in f.lower() for f in all_files)
    has_helpers = any("helpers" in f.lower() for f in all_files)
    has_backup = any("backup" in f.lower() or "old" in f.lower() or "deprecated" in f.lower() for f in all_files)
    entropy_signals = sum([has_utils and has_helpers, has_backup])
    return {"has_utils_and_helpers": has_utils and has_helpers, "has_backup_files": has_backup, "score": 1.0 if entropy_signals == 0 else 0.5}


def check_N4(contents):
    """命名一致性"""
    js_text = "\n".join(c for p, c in contents.items() if p.endswith((".js", ".ts", ".jsx", ".tsx")))
    # 检测同义动词漂移
    verbs = {"get": r'\bget[A-Z]', "fetch": r'\bfetch[A-Z]', "load": r'\bload[A-Z]',
             "handle": r'\bhandle[A-Z]', "on": r'\bon[A-Z]'}
    found = {k: bool(re.search(v, js_text)) for k, v in verbs.items()}
    conflict_count = sum([found["get"] and found["fetch"], found["get"] and found["load"], found["handle"] and found["on"]])
    return {"verb_conflicts": conflict_count, "score": 1.0 if conflict_count <= 1 else 0.5 if conflict_count <= 2 else 0}


# ══════════════════════════════════════════════
# 主检测逻辑
# ══════════════════════════════════════════════

CHECKERS = {
    "C1_CSS变量覆盖": check_C1, "C4_全站等宽": check_C4, "C5_伪元素特效层": check_C5,
    "C11_零框架依赖": check_C11, "J1_中文注释": check_J1, "J2_Canvas2D自绘": check_J2,
    "J7_确定性RNG": check_J7, "J8_数据层版本化": check_J8,
    "N1_零TODO": check_N1, "N5_零调试残留": check_N5, "N3_文件组织熵低": check_N3,
    "N4_命名一致性过高": check_N4,
}


def analyze(target_dir):
    """主分析函数"""
    files, contents = scan_directory(target_dir)

    print(f"\n{'='*60}")
    print(f"  AI 前端代码指纹检测器 v1.0")
    print(f"  目标: {target_dir}")
    print(f"  文件: {sum(len(v) for v in files.values())} 个")
    print(f"{'='*60}\n")

    results = {}
    total_score = 0
    total_weight = 0
    detected = []
    undetected = []

    for fid, fp in FINGERPRINTS.items():
        if fid in CHECKERS:
            result = CHECKERS[fid](contents)
            if isinstance(result, dict):
                score = result.get("score", 0)
            else:
                score = result
        else:
            # 简单正则检测
            score = simple_check(fid, fp, contents)

        weighted = score * fp["weight"]
        results[fid] = {"score": score, "weight": fp["weight"], "weighted": weighted, "desc": fp["desc"]}
        total_score += weighted
        total_weight += fp["weight"]

        if score > 0.6:
            detected.append(fid)
        elif score < 0.3 and fp["weight"] >= 0.5:
            undetected.append(fid)

    # 归一化 (0-100)
    ai_probability = (total_score / max(total_weight, 1)) * 100

    # ── 输出 ──
    print(f"  📊 AI 生成概率: {ai_probability:.0f}%\n")

    print(f"  🔴 高置信度 AI 指纹 (已检测到):")
    for fid in detected:
        fp = FINGERPRINTS[fid]
        r = results[fid]
        bar = "█" * int(r["score"] * 10) + "░" * (10 - int(r["score"] * 10))
        print(f"     {fid:30s} [{bar}] {r['score']:.1f}  {fp['desc'][:50]}")

    print(f"\n  🔵 缺失的指纹 (可能是人类代码):")
    for fid in undetected:
        fp = FINGERPRINTS[fid]
        r = results[fid]
        print(f"     {fid:30s} 缺失 →  {fp['desc'][:50]}")

    print(f"\n  {'─'*50}")
    print(f"  指纹覆盖: {len(detected)}/{len(FINGERPRINTS)}")
    print(f"  加权得分: {total_score:.1f}/{total_weight:.1f}")
    print(f"  AI 概率:  {ai_probability:.0f}%")
    print(f"  {'─'*50}\n")

    return {"probability": ai_probability, "results": results, "files": files}


def simple_check(fid, fp, contents):
    """简单正则检测"""
    text = "\n".join(contents.values())
    patterns = {
        "C2_半透明边框": r'rgba\(\d+,\s*\d+,\s*\d+,\s*0?\.\d+\)',
        "C3_backdrop_filter": r'backdrop-filter\s*:\s*blur',
        "C6_Grid优先": r'display\s*:\s*grid',
        "C7_clamp流体": r'clamp\(', "C8_自定义滚动条": r'::-webkit-scrollbar',
        "C9_letter_spacing微调": r'letter-spacing\s*:\s*0\.0\d+em',
        "C10_统一动效": r'transition\s*:\s*all\s+0\.1[45]s',
        "C12_短语义类名": r'\.hd\b|\.dash\b|\.chip\b|\.deck\b|\.ticker\b',
        "C14_响应式_无障碍": r'prefers-reduced-motion',
        "J3_localStorage版本化": r'localStorage\.(get|set)Item',
        "J4_URL参数驱动": r'URLSearchParams|params\.(get|has)',
        "J6_IntersectionObserver": r'IntersectionObserver',
        "N6_防御性编程均匀": r'try\s*\{',
        "N8_魔法数字反向消失": r'(CONFIG|PARAMS|CONSTANTS)\s*=',
        "N9_第三方洁癖": r'(npm\s+install|node_modules)',
        "N13_0点15秒": r'0\.15s',
    }
    if fid in patterns:
        matches = len(re.findall(patterns[fid], text, re.IGNORECASE))
        return min(1.0, matches * 0.2) if matches > 0 else 0
    return 0.5  # 默认中性


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python3 ai-frontend-fingerprint.py <目标目录>")
        sys.exit(1)

    target = sys.argv[1]
    if not os.path.isdir(target):
        print(f"错误: '{target}' 不是有效目录")
        sys.exit(1)

    result = analyze(target)
