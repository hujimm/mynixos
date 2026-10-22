# lightsail hermes 网关 + Hindsight（已停用）

归档日期：2026-10-22。
原因：不再使用服务器上的 Hermes 与 Hindsight，配置整体退役。

## 这里有什么

| 文件 | 原位置 | 说明 |
|---|---|---|
| `hermes.nix` | `hosts/lightsail/hermes.nix` | Hermes 网关（native + serve + nginx `xixi.liyinuo.tech`） |
| `hindsight.nix` | `hosts/lightsail/hindsight.nix` | Hindsight API/CP + PostgreSQL 容器 |
| `sops.nix` | `hosts/lightsail/sops.nix` | **停用前的完整原文件**，含 Hindsight/hermes 的密钥声明与模板 |
| `secrets/hermes.yaml` | `modules/nixos/security/secrets/hermes.yaml` | 加密的 Hermes 密钥（Telegram/opencode-go/Tavily/GitHub/dashboard） |
| `secrets/hindsight.yaml` | `modules/nixos/security/secrets/hindsight.yaml` | 加密的 Hindsight 密钥（LLM/embedding/reranker/API/CP/DB） |

停用时的改动（live 侧）：

- `hosts/lightsail/default.nix` 去掉 `./hermes.nix`、`./hindsight.nix` 两个 import。
- `hosts/lightsail/sops.nix` 只保留 Vaultwarden；Hindsight/hermes 段已删。
- `modules/nixos/security/.sops.yaml` 去掉 `secrets/hermes.yaml` 与 `secrets/hindsight.yaml` 两条规则。
- `flake.nix` 的 `hermes-agent` 输入**保留**（桌面端 Hermes 仍在用）。

## 数据与备份

服务器上的数据没有随配置删除，仍在：

- `/var/lib/hermes`（会话/工作区/日志，约 48 MB）
- `/var/lib/hindsight/pgdata`（PostgreSQL，约 162 MB）
- 容器 `hindsight`、`hindsight-db`

备份已导出到桌面 `~/lightsail-backup/`：

- `hermes/`：25 个会话、1787 条消息（JSONL/JSON）、`orion-ai-memories.*`、`orion-profile.md`
- `hindsight/`：`hermes-xixi-backup-bank.zip`、`hermes-1-copy-bank.zip`、10-13 的旧 JSON

## 恢复步骤

1. 把 `hermes.nix`、`hindsight.nix` 复制回 `hosts/lightsail/`。
2. 在 `hosts/lightsail/default.nix` 的 `imports` 加回这两项。
3. 从本目录的 `sops.nix` 里把 Hindsight/hermes 的 `secrets` 与 `templates` 段合并回
   `hosts/lightsail/sops.nix`。
4. 把 `secrets/hermes.yaml`、`secrets/hindsight.yaml` 放回
   `modules/nixos/security/secrets/`，并在 `modules/nixos/security/.sops.yaml`
   恢复对应的 `creation_rules`。
5. rebuild。

Hindsight 数据若要恢复：任选

- 直接用原 `/var/lib/hindsight/pgdata`（未删的话）；
- 或新建实例并开启 `HINDSIGHT_API_ENABLE_DOCUMENT_IMPORT_API=true`，
  用 `POST /v1/default/banks/<id>/transfer/import`（`restore`/`merge`）导入 ZIP。

## 备注

- Hermes 的 `$HERMES_HOME/.env` 明文密钥与 `auth.json` 只在服务器上；归档里没有。
  需要的话另外从 `/var/lib/hermes/.hermes/` 取。
- 本目录属于 `modules/_trash/`，不会被任何 `default.nix` 导入。
