# ============================================================================
# 【已弃用 · 2026-10-20】DeepSeek Harness（dsh）桌面 Web 端（整份模块，仅存档）
# ============================================================================
#
# 状态：已停用，从构建中摘除。文件保留在这里只为"以后想恢复"时有个准确的起点。
#
# 为什么停用：
#   不再在桌面上常驻 dsh web（127.0.0.1:3080 常开、额外内存约 250-400MiB）。
#   网页端每次重启生成新 token，使用成本高；日常改用 OpenCode。
#
# 模块做了什么：
#   - 引入 deepseek-harness flake 的 HM 模块，定义 managed profile `web`
#     （bundle: pkgs.dsh.bundles.web-app）；
#   - 起 systemd 用户服务 dsh-web：127.0.0.1:3080，token 鉴权，
#     启动后在 journalctl 打印 http://127.0.0.1:3080/?token=...；
#   - 从 sops 密钥 dsh-env 读取 API key，serve 前需 sops-nix.service。
#
# ---------------------------------------------------------------------------
# 【恢复步骤】按顺序做
# ---------------------------------------------------------------------------
#   1) 把本文件移回 modules/hm/ai-agent/dsh.nix：
#        git mv modules/_trash/hm/dsh.nix modules/hm/ai-agent/dsh.nix
#   2) modules/hm/ai-agent/default.nix 的 imports 里加回： ./dsh.nix
#   3) flake.nix 恢复输入：
#        deepseek-harness.url = "github:Moraxyc/deepseek-harness.nix";
#      以及 nixConfig 里（可选）缓存注释与公钥
#        "deepseek-harness-nix.cachix.org-1:5NrkwLN9veNMhiINtU5ZeV4isXFhFsOwn6Ms7J1M+TA="
#      再执行： nix flake lock --update-input deepseek-harness
#   4) hosts/vostro-3420/default.nix 恢复 overlay（pkgs 里注入 dsh scope）：
#        nixpkgs.overlays = [ inputs.deepseek-harness.overlays.default ];
#   5) 密钥：modules/hm/security/sops.nix 的 sops.secrets 里加回
#        secrets."dsh-env" = { };
#      密文仍在 modules/nixos/security/secrets/api-key.yaml（未删）。
#      解出的明文在 ~/.config/sops-nix/secrets/dsh-env（0400，含 OPENCODE_API_KEY、
#      OPENCODE_GO_API_KEY、DEEPSEEK_API_KEY、OPENROUTER_API_KEY、TAVILY_API_KEY、
#      TELEGRAM_BOT_TOKEN、TELEGRAM_ALLOWED_USERS）。
#   6) 用户数据保留在 ~/.dsh/（DSH_HOME，未删）：profiles/nix-web、sessions、storages、
#      workspace、.credentials.yaml（浏览器会话 secret，token 依赖它）。
#   7) 切换：sudo nixos-rebuild switch --flake .#mynixos
#   8) 取带 token 的地址：
#        journalctl --user -u dsh-web -n 20 | grep "dsh web:"
#
# ---------------------------------------------------------------------------

{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [ inputs.deepseek-harness.homeModules.default ];

  programs.dsh = {
    enable = true;
    profiles.web = {
      bundles = [
        pkgs.dsh.bundles.web-app
      ];
      mode = "managed";
    };

    defaultProfile = config.programs.dsh.profiles.web.materializedName;
  };

  services.dsh = {
    enable = true;
    profile = config.programs.dsh.profiles.web.materializedName;
    environmentFile = "${config.home.homeDirectory}/.config/sops-nix/secrets/dsh-env";
    port = 3080;
  };

  systemd.user.services.dsh-web.Unit.After = [ "sops-nix.service" ];
}
