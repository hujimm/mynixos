# lightsail hermes 网关 + Hindsight（已停用）

归档日期：2026-10-22。不再使用，配置整体退役。

| 文件 | 原位置 |
|---|---|
| `hermes.nix` | `hosts/lightsail/hermes.nix` |
| `hindsight.nix` | `hosts/lightsail/hindsight.nix` |
| `sops.nix` | `hosts/lightsail/sops.nix`（停用前全文） |

停用时的改动：`default.nix` 去掉两个 import；`sops.nix` 只留 Vaultwarden；
`.sops.yaml` 去掉 `secrets/hermes.yaml`、`secrets/hindsight.yaml` 两条规则。
`flake.nix` 的 `hermes-agent` 输入保留（桌面端仍在用）。
两个密钥文件留在 `modules/nixos/security/secrets/`，不在本目录。

数据未删：`/var/lib/hermes`、`/var/lib/hindsight/pgdata`。
备份在 `~/lightsail-backup/`。

## 恢复

1. 把 `hermes.nix`、`hindsight.nix` 复制回 `hosts/lightsail/`，在 `default.nix` 加回 import。
2. 把本目录 `sops.nix` 里的 Hindsight/hermes 段合并回 `hosts/lightsail/sops.nix`。
3. 在 `.sops.yaml` 恢复 `secrets/hermes.yaml`、`secrets/hindsight.yaml` 两条规则。
4. rebuild。
