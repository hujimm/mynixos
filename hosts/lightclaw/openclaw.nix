# OpenClaw 网关（lightclaw）。Home Manager 模块，运行在 openclaw 用户下。
#
# 形态：systemd 用户服务 openclaw-gateway（linger 已开，开机自启）。
# 权限：默认即 OpenClaw 官方的"单信任域"姿态（exec 无审批）；命令以 openclaw 用户执行，
#       该用户有免密 sudo，故 agent 需要时可提权。
# 入口：只监听 127.0.0.1:18789；Telegram 走出站长轮询，不需要任何公网端口。
{ osConfig, pkgs, ... }:

let
  # sops 渲染出的运行时文件路径（只在激活期产生，不进 nix store）。
  secrets = osConfig.sops.secrets;
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

    # 运行时插件：联网搜索的两个 provider（exa / tavily）。
    # 两个都装好；实际用哪个由下面 config.tools.web.search.provider 决定。
    # nix-openclaw 会自动写 plugins.entries.<id>.enabled = true，并把 id 追加进 plugins.allow。
    runtimePlugins = [
      "exa"
      "tavily"
    ];

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
      # 内置记忆（memory-core）的 embedding 用（Cloudflare Workers AI）。
      CF_EMBEDDING_API_KEY = secrets."openclaw-cloudflare-api-token".path;
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

      # A. 内置记忆检索（memory-core）：接 Cloudflare Workers AI 的 OpenAI 兼容端点做
      #    embedding，让 workspace 里的 MEMORY.md / USER.md / memory/*.md 能被语义检索。
      #    记忆系统就是它这一套（workspace Markdown + SQLite 混合检索 + dreaming 巩固 +
      #    provenance 防注入），没有第二套。
      #    注意 memory-core 的 embedding 是**索引身份**的一部分：改 provider/model/sources
      #    后需要 `openclaw memory index --force` 重建索引。
      memory.search = {
        enabled = true;
        provider = "openai-compatible";
        model = "@cf/qwen/qwen3-embedding-0.6b";
        remote = {
          baseUrl = "https://api.cloudflare.com/client/v4/accounts/c6f9a27ce7ae62bb8971fde57e40a28c/ai/v1";
          # 密钥走环境变量注入（值写 sops 文件路径，nix-openclaw 启动时按文件内容解析）。
          apiKey = {
            source = "env";
            provider = "default";
            id = "CF_EMBEDDING_API_KEY";
          };
        };
        # 只索引 memory 来源（MEMORY.md / USER.md / memory/*.md）；不开会话转写索引。
        # 注意：光写 sources 不够——"cross-conversation recall" 会自动把 sessions 加进来
        # （实测确实索引了 90 个 session chunk），所以必须同时关 rememberAcrossConversations。
        # 关它的理由：这台机器内存吃紧，转写索引会多养 transcript worker。
        sources = [ "memory" ];
        rememberAcrossConversations = false;
      };

      # B. 插件白名单：只保留这台机器实际用到的。
      #    exa / tavily 由上面的 runtimePlugins 自动追加进 allow；telegram 是 bundled
      #    channel、由 channels.telegram 激活，不能也不需要放进 allow。
      #    active-memory = 记忆的"升级检索道"（Lane 2）：仅在消息显示回忆意图、且
      #    Lane 1 没命中时，回话前跑一次子 agent 深挖（含当前 agent 的历史）。
      #    它的跨会话部分仍受 memory.search.rememberAcrossConversations=false 约束。
      plugins.allow = [
        "memory-core"
        "active-memory"
        "opencode-go"
        "tavily"
        "document-extract"
        "file-transfer"
        "web-readability"
        "github"
      ];
      # 显式打开（它默认可能不开；上游只在需要时启用这个伴生插件）
      plugins.entries."active-memory".enabled = true;

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
