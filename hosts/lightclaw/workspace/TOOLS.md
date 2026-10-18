# TOOLS.md — 已废弃（内容已并入 AGENTS.md 的 `## Tools` 段）

上游 OpenClaw 已废弃本文件：运行时**不再读它**，本地工具/环境约定的正式位置是
`AGENTS.md` 的 `## Tools` 段（详见 OpenClaw 文档 concepts/agent-workspace 与
reference/templates/TOOLS.md）。本机的工具约定已搬进 `AGENTS.md`，这里不再维护内容。

之所以还保留这个文件并被 nix-openclaw 声明，是因为 `workspace.bootstrapFiles` 的
五个字段（agents/soul/tools/identity/user）**都是必填**，无法单独去掉 `tools`
（见 hosts/lightclaw/openclaw.nix 的注释）。它不会被读，留着无害。

> 注：nix-openclaw 每次激活还会在本文件后追加一份「Nix-managed tools」清单；
> 由于本文件已不被读取，那份清单同样不生效（相关 CLI 已列入 AGENTS.md 的 Tools 段）。
