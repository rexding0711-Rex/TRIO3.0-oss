# TRIO Obsidian 模式

> **定位**：TRIO 的个人轻量笔记层——Obsidian 负责思考的外骨骼，TRIO 负责结构化分析。两者互补，不替代。
> **版本**：v1.0 | **创建日期**：2026-07-06 | **状态**：设计中

---

## 一、为什么需要 Obsidian 模式

TRIO 解决的是"怎么分析对"——三柱子（认知隔离/结构化怀疑/自验证闭环）+ 第四柱（生成性探索）确保分析不出错且有洞察。

但 TRIO 不解决的是：

| TRIO 擅长 | TRIO 不擅长 |
|-----------|------------|
| 结构化尽调/竞品/供应链分析 | 随手记一个想法、一个链接、一个反问 |
| 跑 `/all` 三视角 + 门禁 | 洗澡时冒出的灵感，需要立刻抓住 |
| 输出 MD+PDF+HTML 三件套 | 碎片化阅读笔记、会议随手记 |
| Neo4j 知识图谱查询 | 用 `[[双向链接]]` 在笔记之间跳来跳去 |

**Obsidian 填的是这个洞**：TRIO 的"前台"是重型分析流水线，"后台"需要一个轻量级的想法孵化器。

Karpathy 说得对——笔记不是存档，是**思考的外骨骼**。用自己的话重写 > 高亮/收藏。链接比分类重要。定期回顾旧笔记是"给自己的模型做微调"。

---

## 二、与 TRIO 四柱子的关系

### 2026-07-06 架构更新：三柱 → 四柱

经过 `/all` 三视角分析确认：TRIO 原有的三根柱子全部以防御叙事——"TRIO 防御的不是'出错'，是**安静地出错**"。但 Kimi 代表的洞察/创造/发现功能没有在架构层获得"一等公民"地位。

**新增第四柱：「生成性探索」(Generative Exploration)**，与原有三柱并列：

```
TRIO 4.0 = 
  防御侧：认知隔离 + 结构化怀疑 + 自验证闭环
  进攻侧：生成性探索（反常捕捉 + 参考系切换 + 跨界类比 + 隐藏关联 + 前沿问题）
```

### Obsidian 在四柱中的位置

Obsidian 模式主要服务于**第四柱（生成性探索）**：

| 柱子 | Obsidian 如何参与 |
|------|------------------|
| 认知隔离 | Obsidian 中不同文件夹/标签 = 不同认知立场，"草稿"互不污染 |
| 结构化怀疑 | `[[反证]]` 链接 + 可证伪条件模板 |
| 自验证闭环 | Obsidian Dataview 插件统计"待验证笔记数" |
| **生成性探索** | **Obsidian 的核心战场**——`[[链接]]` 织网、随机漫步、图谱视图发现隐藏关联 |

---

## 三、集成设计——TRIO ↔ Obsidian 的双向通道

### 3.1 文件系统互操作

Obsidian Vault 直接指向 `D:\工作\TRIO\vault\`（或用户指定路径），理由：

- TRIO 的对标库、知识库、训练日志都在 `D:\工作\` 下
- Obsidian 的 `[[链接]]` 可以直接解析到 `D:\工作\对标库\person-benchmark\{人名}\portrait.md`
- 无需导入导出——同一套 Markdown 文件，TRIO 脚本读写、Obsidian 展示编辑

```
D:\工作\
├── vault/                          ← Obsidian Vault 根目录
│   ├── 00-INBOX/                   ← 随手记，未分类
│   ├── 10-Notes/                   ← 读书笔记、会议记录、碎片想法
│   ├── 20-Analysis/                ← 分析草稿（TRIO /all 执行前先在此孵化）
│   ├── 30-Output/                  ← TRIO /all 产出物链接入口
│   └── templates/                  ← Obsidian 模板（可证伪条件、尽调清单等）
├── 对标库/                          ← TRIO 对标库（company-benchmark/person-benchmark）
├── TRIO\ Reports/                  ← TRIO 报告输出
└── 知识库/                          ← TRIO 方法论/模板
```

### 3.2 关键集成点

| 集成点 | 触发方式 | 效果 |
|--------|---------|------|
| `[[人名]]` → portrait.md | Obsidian 内点链接 | 打开人物对标的完整 portrait |
| `/尽调` 从 Obsidian 启动 | Templater 模板 + Shell Commands 插件 | 选中笔记文本 → 一键送入 TRIO `/尽调` |
| 图谱视图 = Neo4j 子图 | Obsidian Graph View | 本地 Markdown 的知识网络可视化（不用写 Cypher） |
| TRIO 分析结果回链 | 分析产出存为 Markdown → 自动出现在 Obsidian | 分析结果可被 `[[链接]]` 发现和使用 |

### 3.3 不做什么

- **不**把 Neo4j 数据同步到 Obsidian（太重，没必要）
- **不**在 Obsidian 里跑 TRIO 门禁（门禁是 TRIO 的职责）
- **不**强制用户使用特定文件夹结构（Obsidian 的优势就是网状自由）

---

## 四、最简启动——10 分钟搭好

### Step 1：安装 Obsidian

```bash
# Linux (AppImage)
wget -O ~/.local/bin/obsidian.AppImage \
  "https://github.com/obsidianmd/obsidian-releases/releases/latest/download/Obsidian-1.11.5.AppImage"
chmod +x ~/.local/bin/obsidian.AppImage

# 或 Windows 端直接下载安装：https://obsidian.md/download
```

### Step 2：创建 Vault

打开 Obsidian → "Open folder as vault" → 选择 `D:\工作\vault\`（首次会自动创建）

### Step 3：安装 3 个核心插件

| 插件 | 用途 | TRIO 关联 |
|------|------|----------|
| **Dataview** | 用查询语法统计笔记元数据 | "待验证笔记数"仪表盘 |
| **Templater** | 高级模板（插入日期、执行脚本） | 可证伪条件模板、尽调启动模板 |
| **Quick Add** | 快捷键捕获想法到 INBOX | 抓取灵感 → 后续可能触发 `/all` |

### Step 4：导入 TRIO 模板

复制 `D:\TRIO 3.0\templates\obsidian\` 下的模板到 Vault 的 `templates/`：
- `falsifiable-condition.md` — 可证伪条件模板
- `dd-starter.md` — 尽调快速启动模板
- `daily-note-trio.md` — 带 TRIO 自检的日记模板

---

## 五、使用场景

| 场景 | 操作 | TRIO 联动 |
|------|------|----------|
| **读书/看文章** | Obsidian 中记笔记，`[[关键词]]` 即时链接 | 读完 → 判断是否需要 `/尽调` 深入 |
| **碎片灵感** | Quick Add → INBOX | 每周回顾 INBOX → 有价值的送 TRIO 分析 |
| **分析前孵化** | 在 Obsidian 中先自由联想 20 分钟 | 再跑 `/all`——带着已有连接进入 |
| **TRIO 交付物回顾** | `/all` 输出放到 vault 后，用图谱视图看连接 | 发现"上次尽调和这次尽调的隐藏关联" |
| **M4 训练日志** | `[[公司名]]` `[[人物名]]` 链接训练笔记到对标库 | Dataview 统计"本月涉及多少家公司/人物" |

---

## 六、与其他 TRIO 模式的关系

```
用户问题
    │
    ├─ 碎片想法 / 读书笔记 / 灵感 → Obsidian 模式（本模式）
    │       │
    │       └─ 孵化成熟 → 送入 TRIO /all /尽调 /竞品
    │
    ├─ 结构化分析 / 尽调 / 竞品 → /all 标准/深度模式
    │       │
    │       └─ 交付物 → 回链到 Obsidian（可被发现和复用）
    │
    └─ 可视化 / 知识图谱 → /图谱可视化 / 3D 图谱
```

**核心原则**：Obsidian 是 TRIO 的"前台孵化器"，TRIO 是 Obsidian 的"后台分析引擎"。一个轻、一个重。一个自由、一个有纪律。各干各的，通过 Markdown 文件系统打通。

---

## 七、设计决策记录

| 决策 | 理由 | 替代方案（被拒绝） |
|------|------|-----------------|
| Vault 放在 `D:\工作\vault\` | 与对标库/知识库文件系统互通，零导入导出 | 独立路径（链接断裂） |
| 不写 Obsidian 插件 | 太重。TRIO 通过文件系统 + 模板集成即可 | 开发专属插件（ROI 不够） |
| 不作为 L0 门禁 | Obsidian 是自由层，不强加 TRIO 纪律 | 把 Obsidian 纳入门禁（会杀死它的优势） |
| 归属 TRIO docs/ 而非独立 | 这是 TRIO 的"内置模式"而非独立系统 | 独立文档（断开与 TRIO 宪法的关系） |

---

## 八、已知限制与 TODO

- [ ] Templater 模板文件尚未创建（`D:\TRIO 3.0\templates\obsidian\` 为空）
- [ ] Dataview 仪表盘配置待设计
- [ ] Shell Commands 插件实现"选中文本 → TRIO /all"的脚本待写
- [ ] 与 M4 训练日志的 Obsidian 模板联动待开发
- [ ] 用户是否已有 Windows 端 Obsidian？需确认安装方案

---

> **相关文档**：
> - [[CORE.md]] — TRIO 核心 SOP（四根柱子）
> - [[../CLAUDE.md]] — 全局指令（E1-E7 认知纪律）
> - `D:\工作\对标库\` — 公司/人物对标库（Obsidian `[[链接]]` 的主要目标）
