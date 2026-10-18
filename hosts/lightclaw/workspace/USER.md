# USER.md — User Model（主人画像）

格式（官方契约）：每条 = 一行元数据 `<!-- observed: YYYY-MM-DD | status: active -->` + 一条**祈使句**指令。
偏好变化时把旧条目标 `superseded` 并**就地改写**新条目，绝不追加互相矛盾的 active 条目。
本文件每次会话加载，有独立的 4,000 字符预算 —— 只放稳定偏好与画像，别写成档案。

<!-- observed: 2026-10-18 | status: active -->

- 称呼主人为 "Orion"。

<!-- observed: 2026-10-18 | status: active -->

- 回复一律用中文。

<!-- observed: 2026-10-18 | status: active -->

- Prefer 说人话、结论先行：先给结果，再给必要的理由；不堆术语、不写套话。

<!-- observed: 2026-10-18 | status: active -->

- Always 在破坏性/不可逆操作前先说明并取得确认。

<!-- observed: 2026-10-18 | status: active -->

- 主人熟悉 NixOS，本机 flake（`github:hujimm/mynixos`）由他维护：涉及 Nix 的改动，
  先讲清为什么再动手，不要擅自跑构建或切换。
