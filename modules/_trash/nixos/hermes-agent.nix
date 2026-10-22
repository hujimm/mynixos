# Hermes 的 NixOS 服务版（2026-10 弃用，现用 modules/hm/ai-agent/hermes.nix 的桌面端）。
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  # 容器模式下 hostUsers 才生效，原生模式必须手动加组，否则 hermes chat 读不了
  # /var/lib/hermes（2770 hermes:hermes）。
  users.users.orion.extraGroups = lib.mkIf config.services.hermes-agent.enable [ "hermes" ];

  services.hermes-agent = {
    enable = true;
    # 不开的话终端里的 hermes 用独立 ~/.hermes，看不到服务积累的会话。
    addToSystemPackages = true;

    settings = {
      model = {
        provider = "opencode-go";
        default = "deepseek-v4-flash";
      };
      auxiliary = {
        vision = {
          provider = "opencode-go";
          model = "mimo-v2.5";
        };
        web_extract = {
          provider = "auto";
          model = "";
        };
        compression = {
          provider = "opencode-go";
          model = "deepseek-v4-flash";
        };
        skills_hub = {
          provider = "auto";
          model = "";
        };
        approval = {
          provider = "auto";
          model = "";
          base_url = "";
        };
        mcp = {
          provider = "auto";
          model = "";
        };
        title_generation = {
          enabled = true;
          provider = "auto";
          model = "";
        };
      };
      compression = {
        enabled = true;
        threshold = 0.7;
        micro_compact = false;
        micro_compact_every_n_turns = 1;
        micro_compact_defrag_threshold_tokens = 2000;
      };
      agent = {
        environment_hint = ''
          操作系统是 NixOS：已启用 flake 和 nix-command，优先使用新的 nix CLI。
        '';
      };
      terminal = {
        backend = "local";
        timeout = 180;
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
        write_approval = false;
        # MEMORY.md 上限，约 800 token。
        memory_char_limit = 2200;
        # USER.md 上限。
        user_char_limit = 1375;
        provider = "";
      };
      security = {
        allow_private_urls = true;
      };

      platforms.telegram = {
        enabled = true;
        reply_to_mode = "first";
        extra = {
          # 群聊场景再加：require_mention = true; rich_messages = false;
        };
      };
    };
  };

  services.hermes-agent.extraPackages = with pkgs; [
    python3
    jq
    file
    tree
    unzip
    sqlite
    openssl
  ];
}
