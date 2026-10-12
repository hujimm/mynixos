# lightsail 上的声明式 hermes 网关（native 模式）。
#
# 选型（与桌面无关，桌面的 hermes 仍走 inputs.hermes-agent）：
#   - 输入用独立的 hermes-agent-main（main 滚动），见 flake.nix；
#   - native 加固 systemd，不起容器（容器模式不能配 backend.mode）；
#   - 网关本身只做 Telegram；backend 只开 serve 且绑回环，
#     远程桌面走 SSH 隧道连 127.0.0.1:9119（绑回环 → 无认证门）；
#   - 记忆接同机 Hindsight 容器：local_external → http://127.0.0.1:8888，
#     tenant key 复用 sops 的 hindsight-api-key。
#
# 密钥（TELEGRAM_BOT_TOKEN / OPENCODE_GO_API_KEY / TAVILY_API_KEY / GITHUB_TOKEN /
# HINDSIGHT_API_KEY）由 sops 渲染成 $HERMES_HOME/.env，见 ./sops.nix 的 hermes-env 模板。
{ config, inputs, ... }:

{
  imports = [ inputs.hermes-agent-main.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    # CLI 进系统 PATH 并全局导出 HERMES_HOME，ssh 上去能共享服务状态
    addToSystemPackages = true;

    # 把 hindsight-client 编进 sealed venv（Nix 运行时装不了包）
    extraDependencyGroups = [ "hindsight" ];

    # 密钥：sops 渲染的 env 文件；非机密项放 environment
    environmentFiles = [ config.sops.templates."hermes-env".path ];
    environment = {
      TELEGRAM_ALLOWED_USERS = "8706786498";
      HINDSIGHT_MODE = "local_external";
      HINDSIGHT_API_URL = "http://127.0.0.1:8888";
    };

    # 给远程桌面连的后端；绑回环 + SSH 隧道，故不触发认证门
    backend = {
      mode = "serve";
      host = "127.0.0.1";
      port = 9119;
    };

    # 声明式 config.yaml（模块深合并；运行时键不在此列，交给 hermes 自管）
    settings = {
      model = {
        default = "deepseek-flash";
        provider = "opencode-go";
        base_url = "https://opencode.ai/zen/go/v1";
        api_mode = "chat_completions";
      };
      providers.opencode-go.models.deepseek-flash.supports_vision = true;

      agent = {
        max_turns = 150;
        reasoning_effort = "low";
      };

      curator.consolidate = true;
      approvals.destructive_slash_confirm = false;
      security.allow_private_urls = true;

      # 外部记忆 provider：接同机自托管 Hindsight
      memory.provider = "hindsight";

      platforms.telegram = {
        enabled = true;
        home_channel = {
          platform = "telegram";
          chat_id = "8706786498";
          name = "orion li";
          user_id = "8706786498";
        };
        extra.command_menu.max_commands = 60;
      };
      # Telegram 状态指示（🟢 Online / 🔴 Offline）
      gateway.platforms.telegram.extra = {
        status_indicator = true;
        status_online = "🟢 Online";
        status_offline = "🔴 Offline";
      };
    };
  };
}
