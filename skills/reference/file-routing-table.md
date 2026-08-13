# 文件落库路由表

> 从 CLAUDE.md 提取。生成任何新文件前，先判断归属。

## 目标路径速查

| 内容类型 | 目标路径 |
|---------|---------|
| TRIO 框架代码/配置 | `D:\TRIO 3.0\` |
| 研究报告/跑批产物 | `D:\工作\TRIO\Reports\` |
| 日志/指标 | `D:\工作\TRIO\日志\` |
| 公司对标 | `D:\工作\对标库\company-benchmark\` |
| 人物对标 | `D:\工作\对标库\person-benchmark\` |
| 行业研究 | `D:\工作\对标库\industry\` |
| 方法论/模板 | `D:\工作\知识库\` |
| 客户项目 | `D:\工作\项目\{项目名}\` |
| 试验/演示/一次性学习资产（demo） | `D:\TRIO 3.0\sandbox\` |
| TRIO-Stock 分支数据（股票库/state/报告） | `D:\工作\TRIO-Stock-数据\`（AgentBranch 原路径为 junction 桥接，透明可访问） |
| 归档/旧版本 | `D:\工作\归档\` |

## 硬约束

1. **框架方法论/协议/脚本/设计系统** → `D:\TRIO 3.0`（OS 内核）
2. **项目交付物/研究报告/尽调产出** → `D:\工作\TRIO\Reports\` 或 `D:\工作\项目\{项目名}\`
3. **公司/人物/行业对标** → `D:\工作\对标库\`
4. **纯方法论/模板/SOP/Prompt** → `D:\工作\知识库\`
5. **不确定属于哪** → **先问用户**，禁止猜测后乱放
6. **二进制文件（.pdf/.docx/.pptx/.xlsx/.db）禁止出现在 TRIO 3.0 根目录**
7. 文件已乱放 → 运行 `bash "/mnt/d/TRIO 3.0/mgmt.sh" classify scan` 自动检测并搬移

> 路由配置文件: `D:\TRIO 3.0\config\file-routing.json`
> 分类命令: `mgmt.sh classify scan`
