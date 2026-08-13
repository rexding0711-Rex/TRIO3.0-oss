# 防御性模式（TRIO 版）

> **吸收自 dsh（DeepSeek Harness）defensive-patterns.md** 2026-08-14。
> 定位：TRIO 是 shell/python 分析引擎，非高并发系统。从 dsh 7 条规则中只取最可能踩的 3 类 bug。每条 = 一类真实缺陷的复发禁令。
> 适用：写/改 scripts/*.sh、scripts/*.py 时读；新增门禁或子进程调用时重点查。

## 规则 1：正交结果独立上报（timeout / signal / exitCode 绝不互相嵌套）

**病**：`subprocess.run(..., timeout=N)` 超时抛 `TimeoutExpired`，但被调进程可能先吞了信号仍以退出码 0 结束——"超时"与"exit 0"可以**并存**。把 `timedOut` 嵌进 `exitCode==0` 的分支判断里，会把一次被中断的运行误读成成功。

**防**：结果对象独立字段 `timed_out` / `signal` / `exit_code`，各自独立上报。汇总时绝不把一个旗标嵌进另一个的 if 分支。

```python
# ❌ 错误：把超时嵌进退出码分支
try:
    r = subprocess.run(cmd, capture_output=True, timeout=30)
    if r.returncode == 0:
        ok = True          # 进程超时被信号杀后仍可能 returncode==0
except subprocess.TimeoutExpired:
    ok = False

# ✅ 正确：三个事实独立保留
try:
    r = subprocess.run(cmd, capture_output=True, timeout=30)
    outcome = dict(ok=r.returncode == 0, timed_out=False, signal=None, exit_code=r.returncode)
except subprocess.TimeoutExpired as e:
    outcome = dict(ok=False, timed_out=True, signal=e.signal, exit_code=None)
```

**自查**：门禁/脚本里所有 `subprocess.run`/`bash -c` 调用，`timed_out` 是否被 `exit_code` 分支吞掉？

## 规则 2：链接形态路径用 lstat→unlink，不递归删除

**病**：`shutil.rmtree` / `rm -rf` 清理 state/临时目录时，会沿符号链接或 Windows junction **下钻进目标**，删除链接指向的真实目录内容。Windows 上 `rmSync(link)` 对 junction 抛 `ERR_FS_EISDIR`。

**防**：删除路径前先 `lstat().is_symlink()` 判断，是链接则 `unlink`（只删链接，拒绝真目录）；递归删除只留给已知的真目录。

```bash
# ❌ 危险：rm -rf 沿链接下钻
rm -rf "$TRIO_ROOT/state/tmp-link"

# ✅ 安全：先判断链接形态
if [ -L "$TRIO_ROOT/state/tmp-link" ]; then
  unlink "$TRIO_ROOT/state/tmp-link"   # 只删链接本身
else
  rm -rf "$TRIO_ROOT/state/tmp-link"   # 确认是真目录才递归
fi
```

**自查**：所有 `rm -rf` 的目标路径，有没有可能是链接/junction？

## 规则 3：不给不可信输出环境变量与可预测路径

**病**：把外部命令/爬取/用户输入的输出喂给另一个命令时，未 scrub 环境变量（`*KEY*`/`*SECRET*`/`*TOKEN*`/`*PASSWORD*`），凭据泄漏进输出/env/spill 文件；临时分析文件用可预测的固定路径+默认权限，引来符号链接竞争与披露。

**防**：
- spawn 命令前 scrub 环境：`env -i` 或显式白名单，丢所有含 KEY/SECRET/TOKEN/PASSWORD 的变量
- 临时文件：0700 私有目录 + 随机名 + `'wx'`/`0o600` 独占打开

```python
import os, tempfile
# 私有目录 + 独占创建
d = tempfile.mkdtemp(prefix="trio-", dir=os.environ.get("TMPDIR", "/tmp"))
fd, path = tempfile.mkstemp(prefix="scratch-", dir=d)
os.close(fd); os.chmod(path, 0o600)   # 仅所有者可读写
```

**自查**：爬取/搜索/外部命令输出是否可能进入 `subprocess` 的 `env`？临时文件是否用固定名+默认权限？

## 规则 4：失败记录带完整原因链（error-cause-chain）

**病**：错误只在顶层 message 里记录（如 `fetch failed`），真因藏在 `error.cause`（`ECONNREFUSED`/bad port）。重看门禁/复盘失败记录时得到死胡同，找不到根因。

**防**：写失败记录/日志/复盘时渲染**完整 cause 链**（顶层 → cause → 逐层），而不是只有顶层 message。门禁失败输出、decision-log 的 basis、复盘时间线都必须包含可追溯的原异常链。

```python
# ❌ 只记顶层
raise RuntimeError(f"调用失败: {exc}")   # exc 是 fetch failed，真因丢失

# ✅ 保留原因链
raise RuntimeError(f"调用失败: {exc}") from exc
# 记录时：print(error_chain(exc))  # 渲染 exc → exc.__cause__ → ...
```

**自查**：门禁/脚本的失败输出是否只显示顶层 message？真因（网络拒绝/超时/子进程退出码）是否可追溯？

## 规则 5：空输出 = 失败，不是成功（empty-response）

**病**：LLM/外部调用返回合法"完成"但**零内容**——被当成成功，一个 round 无进展却标记 `completed`，重试永不跑、错误到不了调用方。

**防**：零内容块是判定边界——provider 返回 `stop` 但无内容 = `EMPTY_RESPONSE`（失败），不是成功。reasoning-only 算内容不误判。无进展的 round 必须触发重试或显式告警。

```python
# ❌ 只看完成标志
if result.finish_reason == "stop":
    ok = True            # 空内容也会走到这里

# ✅ 内容判定
if result.finish_reason == "stop" and result.content.strip():
    ok = True
else:
    ok = False           # 空输出 = 失败，走重试/告警
```

**自查**：TRIO 调 LLM/外部 API 的地方，是否只判断"返回成功"而没判断"返回了有效内容"？

## 总自查

改动 scripts/ 后过一遍五问：
1. 所有子进程的 `timed_out` 是否独立保留？ → 规则 1
2. 所有 `rm -rf` 目标是否确认非链接？ → 规则 2
3. 外部输出是否可能泄漏凭据/写入可预测路径？ → 规则 3
4. 失败记录是否带完整原因链而非顶层 message？ → 规则 4
5. LLM/API 空输出是否被判为失败而非成功？ → 规则 5
