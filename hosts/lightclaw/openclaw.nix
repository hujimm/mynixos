# OpenClaw 网关（lightclaw）。Home Manager 模块，运行在 openclaw 用户下。
#
# 形态：systemd 用户服务 openclaw-gateway（linger 已开，开机自启）。
# 权限：默认即 OpenClaw 官方的"单信任域"姿态（exec 无审批）；命令以 openclaw 用户执行，
#       该用户有免密 sudo，故 agent 需要时可提权。
# 入口：只监听 127.0.0.1:18789；Telegram 走出站长轮询，不需要任何公网端口。
{ osConfig, pkgs, lib, ... }:

let
  # sops 渲染出的运行时文件路径（只在激活期产生，不进 nix store）。
  secrets = osConfig.sops.secrets;

  # ---- Honcho 记忆插件（官方 npm 包 @honcho-ai/openclaw-honcho）----
  # 为什么不走 nix-openclaw 的 runtimePluginSources：它的构建校验（install.mjs）要求插件
  # 自带依赖证据（bundled node_modules 或 npm-shrinkwrap.json），而 honcho 的发布物两者
  # 都没有（依赖靠安装时 npm 现场解析，而 nix-openclaw 禁止构建期跑包管理器）；此外它把
  # 入口写在 package.json 的 `extensions` 而非 `runtimeExtensions`，install.mjs 还会再报
  # "no runtime entry"。所以这里按 install.mjs 的做法自己物化依赖并组装出 OpenClaw 认可的
  # 插件 root，再经 plugins.load.paths 接入（nix-openclaw README 认可的逃生舱）。
  # 升级插件时：改 honchoVersion，重建后按报错更新下面两个 hash。
  gatewayPkg = pkgs.openclaw-gateway; # 必须是 gateway 包：overlay 里 pkgs.openclaw 只是薄包装，
  #                                     而插件 peer 一律链到 ${gateway}/lib/openclaw（同 nix-openclaw）。
  honchoVersion = "1.7.0";

  # 官方 npm tarball（hash = 该 tarball 的 sha256-SRI）。
  honchoSrc = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@honcho-ai/openclaw-honcho/-/openclaw-honcho-${honchoVersion}.tgz";
    hash = "sha256-F1zkDsITr6j6armXJw02gZk+7CU122kOH1NOL4k3vgk=";
  };

  # 固定输出派生（FOD，允许联网）：装生产依赖。输出按 hash 钉死 —— 上游依赖漂移会导致
  # 构建失败而不是静默变化。
  honchoDeps = pkgs.stdenvNoCC.mkDerivation {
    pname = "openclaw-honcho-deps";
    version = honchoVersion;
    dontUnpack = true;
    dontInstall = true;
    dontFixup = true;
    nativeBuildInputs = [
      pkgs.nodejs_24
      pkgs.cacert
    ];
    # 沙箱里没有 CA 库，node/npm 会报 UNABLE_TO_GET_ISSUER_CERT_LOCALLY；显式喂证书。
    env = {
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      NODE_EXTRA_CA_CERTS = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-7VU6Zz6nzzbR1d67quxAS/s3wYxdoSAaulHz4xoBX20=";
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      export npm_config_cache=$TMPDIR/npm-cache
      mkdir -p $out
      tar -xzf ${honchoSrc} -C $out
      cd $out/package
      # --legacy-peer-deps：不解析/不拉 openclaw peer（运行时由 node_modules/openclaw 软链提供）
      npm install --omit=dev --omit=peer --legacy-peer-deps --ignore-scripts --no-audit --no-fund
      rm -rf node_modules/.bin
      runHook postBuild
    '';
  };

  # 组装插件 root：包内容 + node_modules + openclaw peer 软链（= install.mjs 的形状）。
  honchoPlugin = pkgs.runCommand "openclaw-honcho-plugin-${honchoVersion}" { } ''
    cp -r ${honchoDeps}/package $out
    chmod -R u+w $out
    rm -rf $out/node_modules/.bin
    mkdir -p $out/node_modules
    ln -sfn ${gatewayPkg}/lib/openclaw $out/node_modules/openclaw
  '';
in
{
  home.stateVersion = "26.05";

  programs.openclaw = {
    enable = true;

    # workspace 引导文件由 Nix 托管（内容在 ./workspace/*.md）。
    # 声明后 nix-openclaw 会强制 skipBootstrap=true（OpenClaw 不再自己 seed），
    # 且每次激活会用源文件覆盖工作区里的副本 —— 要改就改这里的源文件再重建。
    workspace.bootstrapFiles = {
      agents = ./workspace/AGENTS.md;
      soul = ./workspace/SOUL.md;
      tools = ./workspace/TOOLS.md; # nix-openclaw 会在这份内容后追加生成的工具清单
      identity = ./workspace/IDENTITY.md;
      user = ./workspace/USER.md;
    };

    # 内置工具插件：
    # - summarize 关掉：nix-openclaw 把它的 skill 目录直接当 extraDirs（loader 却找 <dir>/skills），
    #   会持续报 FsSafeError；关掉插件即消除该报错（OpenClaw 自带的 summarize skill 仍在）。
    # - goplaces 出厂默认就是开的，显式关掉（不用 Google Places）。
    bundledPlugins = {
      summarize.enable = false;
      goplaces.enable = false;
    };

    # 联网搜索的两个 provider（exa / tavily）与 Honcho 记忆插件，统一走下面的
    # config.plugins.load.paths 接入，不用 runtimePlugins —— 因为 runtimePlugins 与原始
    # load.paths 在同一实例里互斥（nix-openclaw 断言），而 Honcho 必须走原始路径。
    # 代价：失去模块对 exa/tavily 的自动 allow/入口与 registry 隔离，故下面 allow 与
    # entries 要自己列全。

    # GitHub CLI（nix-openclaw 默认工具链不带 gh）。凭证走下面的 GITHUB_TOKEN，
    # 按 OpenClaw 的 native 解析顺序生效（GH_TOKEN/GITHUB_TOKEN 优先）。
    runtimePackages = [ pkgs.gh ];

    # 密钥经环境变量注入：值写成 sops 文件路径，OpenClaw 启动时读取文件内容
    # （nix-openclaw 的取值约定：值指向已存在的文件即按文件内容解析）。
    environment = {
      OPENCODE_API_KEY = secrets."openclaw-opencode-go-api-key".path;
      OPENCLAW_GATEWAY_TOKEN = secrets."openclaw-gateway-token".path;
      EXA_API_KEY = secrets."openclaw-exa-api-key".path;
      TAVILY_API_KEY = secrets."openclaw-tavily-api-key".path;
      GITHUB_TOKEN = secrets."openclaw-github-token".path;
    };

    config = {
      gateway = {
        mode = "local";
        bind = "loopback"; # 只监听本机
        auth.mode = "token"; # token 值来自 OPENCLAW_GATEWAY_TOKEN
      };

      channels.telegram = {
        dmPolicy = "allowlist"; # 只允许 allowFrom 里的账号私聊，其余静默拒绝
        tokenFile = secrets."openclaw-telegram-bot-token".path;
        allowFrom = [ 8706786498 ];
        # 若 bot 被拉进群：默认只有 @它 才回应（官方模板同款安全默认）。
        groups."*".requireMention = true;
      };

      # owner-only 命令与 exec 审批的授权账号（单主人 bot 应显式设置）。
      commands.ownerAllowFrom = [ "telegram:8706786498" ];

      # 联网搜索默认 provider（exa / tavily 两个插件由 runtimePlugins 自动启用，
      # nix-openclaw 会自动写 plugins.entries.<id>.enabled = true，无需在此重复）。
      tools.web.search.provider = "tavily";

      # A. 语义记忆：机器没有 embedding key，默认的 openai/text-embedding-3-small 会降级成
      # keyword-only（memory_search ~6s、索引 dirty）。直接关掉；索引范围也收窄成只含 memory。
      memory.search.enabled = false;
      memory.search.sources = [ "memory" ];

      # B'. 插件接入（原始形式）：exa / tavily 用 nix-openclaw 生成的包，Honcho 用我们自建的
      #     root。三者都需显式 enabled；Honcho 还必须开 allowConversationAccess（官方明确：
      #     不开就不存任何消息）。
      plugins.load.paths = [
        "${pkgs.openclawRuntimePlugins.exa}"
        "${pkgs.openclawRuntimePlugins.tavily}"
        "${honchoPlugin}"
      ];
      plugins.entries = {
        exa.enabled = true;
        tavily.enabled = true;
        "openclaw-honcho" = {
          enabled = true;
          hooks.allowConversationAccess = true;
          config = {
            # 自建 Honcho（aliyun，经 EasyTier 访问），无需 apiKey。
            baseUrl = "http://10.144.144.1:8010";
            workspaceId = "openclaw";
            # honcho_ask 若太慢可加 timeoutMs（我们的 deriver 有批处理延迟）。
          };
        };
      };

      # B. 插件白名单：只保留这台机器实际用到的。
      #    走原始 load.paths 后模块不再自动追加，故 exa / tavily / openclaw-honcho 都要列；
      #    telegram 是 bundled channel、由 channels.telegram 激活，不能也不需要放进 allow。
      plugins.allow = [
        "memory-core"
        "opencode-go"
        "exa"
        "tavily"
        "openclaw-honcho"
        "document-extract"
        "file-transfer"
        "web-readability"
        "github"
      ];

      # C. 浏览器：机器上没有 chromium，默认启用是坏的，显式关掉。
      browser.enabled = false;

      # E1. 只保留与这台机器用途相关的 OpenClaw 自带技能（workspace/managed 技能不受此限）。
      skills.allowBundled = [
        "browser-automation"
        "clawhub"
        "control-ui"
        "diagnose-gateway"
        "github"
        "healthcheck"
        "openclaw-host-health-check"
        "skill-creator"
        "summarize"
        "tavily"
        "weather"
        "visualize"
        "diagram-maker"
        "node-connect"
        "python-debugpy"
        "node-inspect-debugger"
        "spike"
      ];

      # 模型：用 OpenClaw **内置**的 OpenCode Go provider，ref = "opencode-go/<模型id>"，
      # 无需自定义 provider；凭证走上面的 OPENCODE_API_KEY。
      # 显式把上下文钉成 1000K（Go 目录默认按 200K 处理）。merge 模式只覆盖元数据，
      # 不影响 provider 的目录发现（models.mode 默认即 merge）。
      models.providers.opencode-go.models = [
        {
          id = "deepseek-v4.1-flash";
          name = "DeepSeek V4.1 Flash";
          contextTokens = 1000000;
          input = [
            "text"
            "image"
          ];
        }
        {
          id = "longcat-2.5-preview-free";
          name = "LongCat 2.5 Preview Free";
          contextTokens = 1000000;
          input = [
            "text"
            "image"
          ];
        }
      ];
      # 主模型：对话与 agent 工作。
      agents.defaults.model.primary = "opencode-go/deepseek-v4.1-flash";
      # 辅助模型：标题生成、摘要、进度叙述等短任务。
      agents.defaults.utilityModel = "opencode-go/longcat-2.5-preview-free";
    };
  };

  # nix-openclaw 生成的 systemd 用户单元没有 [Install] 段，默认不会被 enable，
  # 所以开机不会自启。这里补上 WantedBy，让它在 linger 下随 default.target 启动。
  systemd.user.services."openclaw-gateway".Install.WantedBy = [ "default.target" ];
}
