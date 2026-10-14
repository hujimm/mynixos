# lightsail 的系统级 sops：解密 Vaultwarden 管理令牌与 Hindsight 密钥。
#
# 与 aliyun 一致：age 私钥不从文件读取，而是由 SSH host key 派生
# （sops-nix 内部调用 ssh-to-age）。因此本机的 age 公钥已列为
# modules/nixos/security/.sops.yaml 里 secrets/vaultwarden.yaml、
# secrets/hindsight.yaml 与 secrets/hermes.yaml 的收件人。
#
# 取公钥（在 lightsail 上）：
#   nix shell nixpkgs#ssh-to-age -c ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
{ inputs, config, pkgs, ... }:

let
  # Hindsight 的密钥单独一个加密文件（LLM/embedding/reranker 的 API key、自设的
  # API key 与 CP 访问口令、DB 密码）。
  hindsightSops = ../../modules/nixos/security/secrets/hindsight.yaml;
  # hermes 网关的密钥（Telegram bot token、opencode-go / Tavily / GitHub key）。
  hermesSops = ../../modules/nixos/security/secrets/hermes.yaml;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  environment.systemPackages = [ pkgs.sops ];

  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ../../modules/nixos/security/secrets/vaultwarden.yaml;

    secrets."vaultwarden-admin-token" = { };

    # 渲染成 systemd EnvironmentFile 供 vaultwarden 服务读取。
    # 明文只在激活期从 /run/secrets 产生，不落 world-readable 的 nix store。
    templates."vaultwarden-env" = {
      content = "ADMIN_TOKEN=${config.sops.placeholder."vaultwarden-admin-token"}";
      mode = "0400";
    };

    # ---- Hindsight（占位：值由你用 sops 填）----
    # 单 key 文件（secrets/hindsight.yaml），故逐条显式指定 sopsFile。
    secrets."hindsight-opencode-go-api-key".sopsFile = hindsightSops;
    secrets."hindsight-cloudflare-api-token".sopsFile = hindsightSops;
    secrets."hindsight-nvidia-api-key".sopsFile = hindsightSops;
    secrets."hindsight-api-key".sopsFile = hindsightSops;
    secrets."hindsight-cp-access-key".sopsFile = hindsightSops;
    secrets."hindsight-db-password".sopsFile = hindsightSops;

    # 应用容器的密钥环境变量（非密项写在 hindsight.nix 的 environment 里）。
    # 明文只在激活期从 /run/secrets 产生，不落 nix store。
    templates."hindsight-env" = {
      content = ''
        HINDSIGHT_API_DATABASE_URL=postgresql://hindsight:${config.sops.placeholder."hindsight-db-password"}@hindsight-db:5432/hindsight_db
        HINDSIGHT_API_LLM_API_KEY=${config.sops.placeholder."hindsight-opencode-go-api-key"}
HINDSIGHT_API_LLM_1_API_KEY=${config.sops.placeholder."hindsight-opencode-go-api-key"}
        HINDSIGHT_API_EMBEDDINGS_OPENAI_API_KEY=${config.sops.placeholder."hindsight-cloudflare-api-token"}
        HINDSIGHT_API_RERANKER_LITELLM_SDK_API_KEY=${config.sops.placeholder."hindsight-nvidia-api-key"}
        # 保险：LiteLLM 的 nvidia_nim provider 也读这个环境变量，与上面的 api_key 同值。
        NVIDIA_NIM_API_KEY=${config.sops.placeholder."hindsight-nvidia-api-key"}
        HINDSIGHT_API_TENANT_API_KEY=${config.sops.placeholder."hindsight-api-key"}
        HINDSIGHT_CP_DATAPLANE_API_KEY=${config.sops.placeholder."hindsight-api-key"}
        HINDSIGHT_CP_ACCESS_KEY=${config.sops.placeholder."hindsight-cp-access-key"}
      '';
      mode = "0400";
    };

    # 数据库容器的初始化变量（官方 postgres 镜像读取 POSTGRES_*）。
    templates."hindsight-db-env" = {
      content = ''
        POSTGRES_USER=hindsight
        POSTGRES_DB=hindsight_db
        POSTGRES_PASSWORD=${config.sops.placeholder."hindsight-db-password"}
      '';
      mode = "0400";
    };

    # ---- hermes 网关（占位：值由你用 sops 填，见 secrets/hermes.yaml）----
    # 单 key 文件（secrets/hermes.yaml），故逐条显式指定 sopsFile。
    secrets."hermes-telegram-bot-token".sopsFile = hermesSops;
    secrets."hermes-opencode-go-api-key".sopsFile = hermesSops;
    secrets."hermes-tavily-api-key".sopsFile = hermesSops;
    secrets."hermes-github-token".sopsFile = hermesSops;
    # 公网反代后的 dashboard 登录门：密码 + 稳定签名密钥（否则每次重启掉登录）
    secrets."hermes-dashboard-password".sopsFile = hermesSops;
    secrets."hermes-dashboard-secret".sopsFile = hermesSops;

    # hermes 的 $HERMES_HOME/.env：本文件密钥 + 复用 hindsight 的 tenant key。
    # 明文只在激活期从 /run/secrets 产生，不落 world-readable 的 nix store。
    templates."hermes-env" = {
      content = ''
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder."hermes-telegram-bot-token"}
        OPENCODE_GO_API_KEY=${config.sops.placeholder."hermes-opencode-go-api-key"}
        TAVILY_API_KEY=${config.sops.placeholder."hermes-tavily-api-key"}
        GITHUB_TOKEN=${config.sops.placeholder."hermes-github-token"}
        HINDSIGHT_API_KEY=${config.sops.placeholder."hindsight-api-key"}
        HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=${config.sops.placeholder."hermes-dashboard-password"}
        HERMES_DASHBOARD_BASIC_AUTH_SECRET=${config.sops.placeholder."hermes-dashboard-secret"}
      '';
      mode = "0400";
    };
  };
}
