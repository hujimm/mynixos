# lightsail 上的声明式 hermes 网关（native 模式）。
#
# 选型（与桌面无关，桌面的 hermes 仍走 inputs.hermes-agent）：
#   - 输入用独立的 hermes-agent-server（钉最新 release tag v0.21.7），见 flake.nix；
#   - native 加固 systemd，不起容器（容器模式不能配 backend.mode）；
#   - 网关本身只做 Telegram；backend 只开 serve 且绑回环，
#     远程桌面走 SSH 隧道连 127.0.0.1:9119（绑回环 → 无认证门）；
#   - 记忆接同机 Hindsight 容器：local_external → http://127.0.0.1:8888，
#     tenant key 复用 sops 的 hindsight-api-key。
#
# ⚠️ Hindsight 自 v0.21.5 起「去内置化」，且是**目录插件**。但目录插件经
#    extraPlugins 软链后 provider 名 = 目录名（plugins/memory 发现用 child.name，
#    模块又会加 nix-managed- 前缀），对不上 memory.provider="hindsight"。
#    故采用社区验证做法（sylvesterroos/dotfiles）：把它重打成 pip 包，暴露
#    entry-point 组 hermes_agent.memory_providers 的 "hindsight"。local_external
#    只需 hindsight-client。
#
# ⚠️ 插件不能用模块的 `extraPythonPackages` 注入！见 moduleCommon.nix:679 的
#    effectivePackage：一旦 extraPythonPackages/extraDependencyGroups 任一非空，
#    就会 `cfg.package.override { extraDependencyGroups = cfg....; }`，把 flake
#    default（=full，含 messaging/daytona…）的 extras 覆盖成 [] → Telegram 适配器
#    因缺 python-telegram-bot 起不来、hindsight-client 运行时缺 aiohttp。故这里
#    直接 override `package` 本身，在 full 之上叠加插件，模块级那两个选项留空。
#
# 密钥（TELEGRAM_BOT_TOKEN / OPENCODE_GO_API_KEY / TAVILY_API_KEY / GITHUB_TOKEN /
# HINDSIGHT_API_KEY）由 sops 渲染成 $HERMES_HOME/.env，见 ./sops.nix 的 hermes-env 模板。
{
  config,
  inputs,
  pkgs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # flake 的 default 包 = full（含 messaging/daytona 等 extras）。用它做基准，
  # 也用它自带的解释器构建插件（避免与 config.services.hermes-agent.package 递归）。
  hermesBase = inputs.hermes-agent-server.packages.${system}.default;
  py = hermesBase.python.pkgs;

  # ── Hindsight 插件源码（目录插件 → pip 包）──
  # v0.21.7 的 plugin-catalog/hindsight.yaml 把插件钉在 d56c4acd（v1.2.1）。
  # 用 codeload tarball 的平铺 sha256（可直接算，无需 fakeHash/prefetch）。
  hindsightPluginSrc = pkgs.stdenvNoCC.mkDerivation {
    pname = "hermes-plugin-hindsight-src";
    version = "1.2.1";
    src = pkgs.fetchurl {
      # 必须给带 .tar.gz 的 name，否则 store 路径无扩展名，unpackPhase 认不出 gzip。
      name = "hindsight-plugin-d56c4acd.tar.gz";
      url = "https://codeload.github.com/vectorize-io/hindsight/tar.gz/d56c4acdf59c41957613d399094cdf8c489b060c";
      hash = "sha256-utu+6lXhRIe/owabJiXUIl+q9i+K2TB6Yt7vTXb2C3s=";
    };
    installPhase = ''
      mkdir -p $out
      cp -r hindsight-integrations/hermes/. $out/
      rm -rf $out/tests   # 只留运行所需
    '';
  };

  # hindsight-client：local_external 唯一需要的库。它的依赖（aiohttp/aiohttp-retry/
  # pydantic/urllib3/yarl/dateutil/typing-extensions）都在 full 的 sealed venv 里，
  # 故本包**不声明依赖**——声明会触发 sealed-venv 冲突检查而构建失败。
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

  # 把目录插件重打包为 pip 包，声明 hermes_agent.memory_providers entry point。
  hermes-plugin-hindsight = py.buildPythonPackage {
    pname = "hermes-plugin-hindsight";
    version = "1.2.1";
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
      version = "1.2.1"
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
    # 导入的是 Hermes 自己的模块，只有 venv 提供；且不做 runtime dep 校验。
    dontCheckRuntimeDeps = true;
    dontUsePythonImportsCheck = true;
  };

  # 主机通用命令行工具：既装进系统 PATH（ssh/运维/其它服务都能用），也交给
  # hermes 服务。systemd 服务的 PATH 是模块显式构造的（不含系统 profile），
  # 所以必须同时进 extraPackages，agent 才看得到这些命令。
  # 其中 python3 是桌面端 Desktop SSH 探针需要的（它经 SSH 执行 `python3 -`）。
  commonTools = with pkgs; [
    python3
    gh # GitHub CLI，自动读环境里的 GITHUB_TOKEN/GH_TOKEN
    git
    ripgrep # rg
    fd
    ffmpeg
    nodejs # 含 node 与 npm
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

  # 上游模块没有接 restartTriggers：只改 settings/hermesHomeFiles 的重建不会重启
  # 网关，运行中的进程仍用旧配置。用 NixOS 官方 systemd.restartTriggers 做一个
  # sentinel，声明内容一变就自动重启两个服务，省去每次手动重启。
  configSentinel = pkgs.writeText "hermes-lightsail-config-sentinel" (
    builtins.toJSON {
      inherit (config.services.hermes-agent)
        settings
        hermesHomeFiles
        environment
        environmentFiles
        ;
    }
  );
in
{
  imports = [ inputs.hermes-agent-server.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    # CLI 进系统 PATH 并全局导出 HERMES_HOME，ssh 上去能共享服务状态
    addToSystemPackages = true;

    # 在 full 之上叠加 hindsight 插件（保留 messaging/daytona 等 extras）。
    # 不要改用模块的 extraPythonPackages——那会覆盖掉 full 的 extras（见文件头）。
    package = hermesBase.override {
      extraPythonPackages = [ hermes-plugin-hindsight ];
    };

    # agent 的 PATH（服务级）。见文件头 commonTools 的说明。
    extraPackages = commonTools;

    # 密钥：sops 渲染的 env 文件；非机密项放 environment
    environmentFiles = [ config.sops.templates."hermes-env".path ];
    environment = {
      TELEGRAM_ALLOWED_USERS = "8706786498";
      # 公网反代后的登录门用户名（非机密）；密码与签名密钥走 sops（见 ./sops.nix）。
      HERMES_DASHBOARD_BASIC_AUTH_USERNAME = "orion";
    };

    # 给远程桌面/浏览器连的后端。绑 0.0.0.0 让 nginx 可用域名反代，并触发出
    # 登录门（认证）。9119 不对外开放（防火墙只放 80/443，nginx 走回环访问它）。
    backend = {
      mode = "serve";
      host = "0.0.0.0";
      port = 9119;
    };

    # Hindsight 插件自己的配置。优先级高于 env（HINDSIGHT_MODE 只在“无 config.json”
    # 时才读 env），所以这里显式声明，避免踩优先级坑。
    hermesHomeFiles."hindsight/config.json" = builtins.toJSON {
      mode = "local_external";
      api_url = "http://127.0.0.1:8888";
      # 存完一条记忆后，后台最多等多久（秒）看它能否被搜到。默认 10；这台机
      # Hindsight 存得慢，调到 30 以减少“刚聊完却想不起来”的次数（后台等待，
      # 不影响回复速度）。
      prefetch_retain_drain_timeout = 30;

      # 【治跨会话重复】Hindsight 默认「按标签分桶」写结论，而本插件会给每条记录
      # 自动贴 session:<id> 标签，于是同一件事在不同会话各生成一条结论（实测三个
      # 会话各 84/74/66 条）。shared = 写结论时忽略会话标签、全局合并；会话标签
      # 仍留在原始记录上，供按会话检索。
      observation_scopes = "shared";

      # 攒够 3 轮（用户一句 + agent 一句 = 1 轮）打包存一次，减少原料与 LLM 调用。
      # 1 = 每轮立刻存（上游默认）。会话结束时未攒满的会补发，不会丢。
      retain_every_n_turns = 3;

      # 过滤明显不相关的召回：不设的话，问无关问题也会塞满 recall_max_tokens 的
      # “最不坏”记忆。门槛按 reranker 分；本机重排是 NVIDIA 的，刻度按实测校准。
      recall_min_scores = {
        reranker = 0.45;
      };
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
        execution_guidance = false; # 唯一专给 deepseek 系的
        tool_use_enforcement = false; # Tool-use enforcement
        task_completion_guidance = false; # Finishing the job
        parallel_tool_call_guidance = false; # Parallel tool calls
        disabled_toolsets = [
          "browser"
          "computer_use"
          "image_gen"
          "connections"
          "tts"
        ];
      };

      # 自动起标题改用 opencode-go 的 glm-5.3-flash（默认走 deepseek-flash 会 400）
      auxiliary = {
        title_generation = {
          provider = "opencode-go";
          model = "glm-5.3-flash";
        };
        background_review.enabled = false;
      };

      curator.consolidate = true;
      approvals.destructive_slash_confirm = false;
      security.allow_private_urls = true;

      # 与本地 (~/.hermes/config.yaml) 一致的禁用技能清单
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

      # 外部记忆 provider：接同机自托管 Hindsight
      plugins.enabled = [ "hindsight" ];
      memory = {
        provider = "hindsight";
        # 官方建议：用 hindsight 时关掉内置 flat-file 记忆，避免模型偏好内置
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
      # Telegram 状态指示（🟢 Online / 🔴 Offline）
      gateway.platforms.telegram.extra = {
        status_indicator = true;
        status_online = "🟢 Online";
        status_offline = "🔴 Offline";
      };

      # Copilot 本机不用，但 .env 里那个 ghp_ 令牌会被 Copilot 探测认成“有凭证”，
      # 每次模型目录轮询就打一条 copilot_auth 警告。排除检查在凭证探测之前，
      # 排除后警告消失；令牌本身留着给 GitHub 技能用。
      model_catalog.excluded_providers = [
        "copilot"
        "copilot-acp"
      ];
    };
  };

  # 声明相关的 settings/hermesHomeFiles/environment 一旦变化，就自动重启网关与后端
  # （NixOS 官方 systemd.restartTriggers）。
  systemd.services.hermes-agent.restartTriggers = [ configSentinel ];
  systemd.services.hermes-backend.restartTriggers = [ configSentinel ];

  # ── 公网入口：nginx + Let's Encrypt 反代本机后端 9119 ──
  # 复用 vaultwarden.nix/hindsight.nix 的 security.acme.defaults.email 与全局 TLS 参数。
  # 后端已绑 0.0.0.0 且启用登录门；9119 本身不对外（防火墙只放 80/443，nginx 走回环）。
  services.nginx.virtualHosts."xixi.liyinuo.tech" = {
    enableACME = true;
    forceSSL = true;
    extraConfig = "client_max_body_size 128M;";
    locations."/" = {
      proxyPass = "http://127.0.0.1:9119";
      proxyWebsockets = true;
      extraConfig = ''
        # /api/ws、/api/pty 是长连接，超时要放宽
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  # 通用命令行工具装到系统全局（ssh/运维/其它服务可用）；同一份列表也给了
  # hermes 服务。python3 是桌面端 Desktop SSH 探针所需，见文件头 commonTools。
  environment.systemPackages = commonTools;
}
