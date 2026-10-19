# ============================================================================
# 【已弃用 · 2026-10-19】lightclaw 的 OpenClaw 工作区文件（bootstrap，仅存档）
# ============================================================================
#
# 状态：已停用。原路径 hosts/lightclaw/workspace/，经
# modules/_trash/nixos/lightclaw-openclaw.nix 里的 workspace.bootstrapFiles 物化到
# /home/openclaw/.openclaw/workspace/（AGENTS.md / SOUL.md / IDENTITY.md / USER.md；
# TOOLS.md 因 nix-openclaw 强制拼工具清单、已废弃，是被一个 activation 钩子删掉的）。
#
# 这些文件是给 agent 的运行时人设/规则，含大量与本库偏好绑定的内容（只用中文、
# 记忆写侧规则、心跳收敛等），恢复 OpenClaw 时值得原样搬回。
#
# 恢复：
#   git mv modules/_trash/nixos/lightclaw-workspace hosts/lightclaw/workspace
#   并恢复 modules/_trash/nixos/lightclaw-openclaw.nix（它引用这些文件）
#
# 注意：workspace 内容会随会话被 agent 自己写（Nix 只托管 bootstrap 那几个），
# 归档的这份是"最后一次声明的 Nix 版本"，不是运行时数据。
