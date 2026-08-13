# Post-Session 自增强处理

> **触发**: 每次 Claude Code 会话结束后（Post-Session Hook）
> **配置**: 需要 `.claude/settings.local.json` 中的 Hook 配置
> **版本**: 1.0 | **创建**: 2026-06-24

## 配置方式

在 `~/.claude/settings.local.json` 或项目 `.claude/settings.json` 中添加：

```json
{
  "hooks": {
    "PostSession": [{
      "matcher": "",
      "command": "bash /mnt/d/TRIO\\ 3.0/mgmt.sh post-session"
    }]
  }
}
```

## 处理流程

```
会话结束
    ↓
Post-Session Hook 触发
    ↓
mgmt.sh post-session 执行:
    1. 扫描本次会话产出的文件变更
       - runs/ 新增 run 数
       - config/ 变更（角色/场景）
       - knowledge/ 变更
    2. 更新 metrics.md
    3. 如有新增 run → 评估是否需要提取模式
    4. 如有 config 变更 → 记录到变更日志
    5. 如有 knowledge 变更 → 触发 kb-refresh 更新
    6. 输出处理摘要
```

## mgmt.sh post-session 子命令

```bash
cmd_post_session() {
    local now
    now=$(date '+%Y-%m-%d %H:%M')
    
    echo "📋 Post-Session 处理 — $now"
    echo ""
    
    # 1. 扫描 runs/
    local new_runs
    new_runs=$(find "$TRIO_ROOT/runs/" -maxdepth 1 -type d -newer "$CONFIG_DIR/last_session.txt" 2>/dev/null | wc -l)
    echo "  新 run: $new_runs 个"
    
    # 2. 更新 metrics.md
    # (读取当前 metrics.md → 更新数字 → 写回)
    
    # 3. 检查是否需要提取模式
    # (如有新 run → 提醒 /能力镜像 累积数据)
    
    # 4. 记录变更
    echo "$now	post-session	处理完成，$new_runs 个新 run" >> "$HISTORY_FILE"
    
    # 5. 更新 last_session 时间戳
    date '+%Y-%m-%d %H:%M' > "$CONFIG_DIR/last_session.txt"
}
```

## 当前状态

⚠️ **Post-Session Hook 尚未配置**。需要：
1. 确认 Claude Code 版本 ≥ v2.1.169（支持 Post-Session Hook）
2. 在 settings.local.json 中添加 Hook 配置
3. 在 mgmt.sh 中实现 `post-session` 子命令

## 替代方案

如果不配置 Hook，可以手动在每次重要会话后运行：
```
bash /mnt/d/TRIO\ 3.0/mgmt.sh post-session
```
