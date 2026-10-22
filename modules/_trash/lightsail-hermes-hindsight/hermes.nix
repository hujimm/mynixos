# lightsail 上的 Hermes 网关（native 模式，2026-10 弃用），记忆接同机 Hindsight。
#
# 三个坑：
#   · Hindsight 自 v0.21.5 起是「目录插件」，经 extraPlugins 软链后 provider 名会对不上
#     memory.provider="hindsight"（发现用目录名，模块还会加 nix-managed- 前缀），
#     所以要重打成 pip 包、声明 hermes_agent.memory_providers entry point。
#   · 插件不能用模块的 extraPythonPackages 注入：只要它或 extraDependencyGroups 非空，
#     模块就会 override package 并把 full 的 extras 覆盖成 []，python-telegram-bot 缺失，
#     适配器起不来。这里直接 override package 本身。
#   · 上游模块没接 restartTriggers，只改 settings 的重建不会重启网关。
{
  config,
  inputs,
  pkgs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # flake 的 default 包 = full（含 messaging/daytona 等 extras）。
  hermesBase = inputs.hermes-agent.packages.${system}.default;
  py = hermesBase.python.pkgs;

  # 目录插件 → pip 包。版本跟着 plugin-catalog 钉的 f843f173（1.2.2）：1.2.1 会静默丢弃
  # observation_scopes="shared"，也没有 recall_min_scores。
  # 哈希只能用 codeload 的 tar.gz 地址算，`gh api repos/.../tarball` 的字节不同。
  hindsightPluginSrc = pkgs.stdenvNoCC.mkDerivation {
    pname = "hermes-plugin-hindsight-src";
    version = "1.2.2";
    src = pkgs.fetchurl {
      # 不带 .tar.gz 后缀时 store 路径无扩展名，unpackPhase 认不出 gzip。
      name = "hindsight-plugin-f843f173.tar.gz";
      url = "https://codeload.github.com/vectorize-io/hindsight/tar.gz/f843f173bb41f001e322cc83c917371639e47fbf";
      hash = "sha256-e4KPX3ELUnacvOcNdo63EgYobJph4OrqKGsLda4QqgU=";
    };
    installPhase = ''
      mkdir -p $out
      cp -r hindsight-integrations/hermes/. $out/
      rm -rf $out/tests
    '';
  };

  # local_external 只需要 hindsight-client。不声明依赖：它的依赖都在 full 的 sealed venv 里，
  # 声明会触发 sealed-venv 冲突检查而构建失败。
  hindsight-client = py.buildPythonPackage {
    pname = "hindsight-client";
    version = "0.10.3";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/54/31/5157bd9f73dca7ef2516470ff85818e03d6167f031cfcc96ff1c263ebc12/hindsight_client-0.10.3-py3-none-any.whl";
      hash = "sha256-tNDRu8KdzU7yWkojoIpIBG1TN7cEva+rsC0AENKZoGg=";
    };
    dontCheckRuntimeDeps = true;
  };

  hermes-plugin-hindsight = py.buildPythonPackage {
    pname = "hermes-plugin-hindsight";
    version = "1.2.2";
    src = hindsightPluginSrc;
    pyproject = true;
    postPatch = ''
      mkdir hermes_hindsight
      mv *.py plugin.yaml hermes_hindsight/
      cat > pyproject.toml <<'EOF'
      [build-system]
      requires = ["setuptools"]
      build-backend = "setuptools.build_meta"

      [project]
      name = "hermes-plugin-hindsight"
      version = "1.2.2"
      dependencies = ["hindsight-client"]

      [project.entry-points."hermes_agent.memory_providers"]
      hindsight = "hermes_hindsight"

      [tool.setuptools]
      packages = ["hermes_hindsight"]
      package-data = { hermes_hindsight = ["plugin.yaml"] }
      EOF
    '';
    build-system = [ py.setuptools ];
    dependencies = [ hindsight-client ];
    dontCheckRuntimeDeps = true;
    dontUsePythonImportsCheck = true;
  };

  # hermes 服务的 PATH 是模块显式构造的（不含系统 profile），所以这些命令必须同时
  # 进 extraPackages，agent 才看得到。python3 是桌面端 SSH 探针所需。
  commonTools = with pkgs; [
    python3
    gh
    git
    ripgrep
    fd
    ffmpeg
    nodejs
    jq
    yq-go
    curl
    wget
    unzip
    zip
    gnutar
    gzip
    tree
    which
    openssl
    sqlite
  ];

  configSentinel = pkgs.writeText "hermes-lightsail-config-sentinel" (
    builtins.toJSON {
      inherit (config.services.hermes-agent)
        settings
        hermesHomeFiles
        environment
        ;
    }
  );
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    package = hermesBase.override {
      extraPythonPackages = [ hermes-plugin-hindsight ];
    };

    extraPackages = commonTools;

    environment = {
      TELEGRAM_ALLOWED_USERS = "8706786498";
      HERMES_DASHBOARD_BASIC_AUTH_USERNAME = "orion";
    };

    # 绑 0.0.0.0 让 nginx 用域名反代（非回环即触发登录门）；9119 本身不对外开放。
    backend = {
      mode = "serve";
      host = "0.0.0.0";
      port = 9119;
    };

    # Hindsight 配置的优先级高于 env（HINDSIGHT_MODE 只在没有 config.json 时才读 env）。
    hermesHomeFiles."hindsight/config.json" = builtins.toJSON {
      mode = "local_external";
      api_url = "http://127.0.0.1:8888";
      # 存完一条记忆后后台最多等多久看它能否被搜到；这台机存得慢，默认 10 秒会"刚聊完想不起来"。
      prefetch_retain_drain_timeout = 30;

      # 默认按标签分桶写结论，插件又会自动贴 session:<id>，同一件事每个会话各一条；
      # shared 让写结论时忽略会话标签、全局合并（标签仍留在原始记录上）。
      observation_scopes = "shared";

      # 默认异步召回要等上一轮落盘变可见，快节奏对话里一次都注不进来。
      # true = 每轮同步召回，代价是每轮多零点几秒到几秒（超 8 秒则这轮空手）。
      recall_sync = true;

      # 每轮 retain 附带的背景说明，参与判断第一人称「我」指谁；英文默认模板会把
      # 结论语种带偏。不含姓名，避免姓名被反复写进结论。
      retain_context = "用户与助手嬉嬉在其自托管 NixOS 服务器上的日常对话";

      # 每轮立刻存；攒批会让"刚说过的话"好几轮之后才搜得到。
      retain_every_n_turns = 1;

      # 门槛会被服务端与插件各应用一次。原值 0.45 等于把注入彻底关死（逐字命中也只有
      # 0.37）；实测 0.02 是相关 5/6、无关 0/6，0.03 起相关掉到 3/6。
      recall_min_scores = {
        reranker = 0.01;
      };
    };

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
        # 这四项是给 deepseek 系的执行引导，关掉。
        execution_guidance = false;
        tool_use_enforcement = false;
        task_completion_guidance = false;
        parallel_tool_call_guidance = false;
        disabled_toolsets = [
          "browser"
          "computer_use"
          "image_gen"
          "connections"
          "tts"
        ];
      };

      auxiliary = {
        title_generation = {
          provider = "opencode-go";
          model = "longcat-2.5-preview-free";
        };
        background_review.enabled = false;
      };

      curator.consolidate = true;
      approvals.destructive_slash_confirm = false;
      security.allow_private_urls = true;

      skills.disabled = [
        "findmy"
        "imessage"
        "apple-reminders"
        "apple-notes"
        "design-md"
        "manim-video"
        "ascii-video"
        "p5js"
        "popular-web-designs"
        "baoyu-infographic"
        "architecture-diagram"
        "airtable"
        "competitor-news-monitor"
        "grounded-citations"
        "systematic-debugging"
        "test-driven-development"
        "spike"
        "codebase-inspection"
        "dogfood"
        "inspecting-hermes-desktop-dom"
        "blocked-page-recovery"
        "requesting-code-review"
        "arxiv"
        "xurl"
        "computer-use"
        "humanizer"
        "obsidian"
        "llm-wiki"
        "box"
        "claude-code"
        "claude-design"
        "codex"
        "email-inbox-triage"
        "gif-search"
        "google-workspace"
        "himalaya"
        "notion"
        "opencode"
        "simplify-code"
        "songsee"
        "songwriting-and-ai-music"
        "teams-meeting-pipeline"
      ];

      plugins.enabled = [ "hindsight" ];
      memory = {
        provider = "hindsight";
        # 官方建议：用外部 provider 时关掉内置 flat-file 记忆，避免模型偏好内置。
        memory_enabled = false;
        user_profile_enabled = false;
      };

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
      gateway.platforms.telegram.extra = {
        status_indicator = true;
        status_online = "🟢 Online";
        status_offline = "🔴 Offline";
      };

      # Copilot 本机不用；不排除的话每次模型目录轮询都会打一条 copilot_auth 警告。
      model_catalog.excluded_providers = [
        "copilot"
        "copilot-acp"
      ];
    };
  };

  # 内存见底时按重要性排死亡顺序：网关 -500（一死 Telegram 就断），
  # serve 后端 +200（重启即恢复）。记忆容器的分见 ./hindsight.nix。
  systemd.services.hermes-agent.serviceConfig.OOMScoreAdjust = -500;
  systemd.services.hermes-backend.serviceConfig.OOMScoreAdjust = 200;

  systemd.services.hermes-agent.restartTriggers = [ configSentinel ];
  systemd.services.hermes-backend.restartTriggers = [ configSentinel ];

  services.nginx.virtualHosts."xixi.liyinuo.tech" = {
    enableACME = true;
    forceSSL = true;
    extraConfig = "client_max_body_size 128M;";
    locations."/" = {
      proxyPass = "http://127.0.0.1:9119";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  environment.systemPackages = commonTools;
}
