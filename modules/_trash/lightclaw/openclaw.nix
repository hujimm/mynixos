# OpenClaw 网关（HM 模块，2026-10 弃用）。nginx 反代见 ./nginx.nix，
# agent 人设在 ./workspace/。
#
# 两个跟 nix-openclaw 版本绑定的坑：`bootstrapFiles.tools` 是必填且每次激活都会物化
# TOOLS.md，而上游运行时早已不读这个文件（工具约定搬到 AGENTS.md 了），所以下面用
# activation 把它删掉；生成的 systemd 用户单元没有 [Install] 段，需自己补 WantedBy。
{ config, pkgs, lib, ... }:

{
  home.stateVersion = "26.05";

  programs.openclaw = {
    enable = true;

    # 声明后 nix-openclaw 强制 skipBootstrap，每次激活用源文件覆盖工作区副本；
    # 要改就改 ./workspace/ 里的源文件再重建。
    workspace.bootstrapFiles = {
      agents = ./workspace/AGENTS.md;
      soul = ./workspace/SOUL.md;
      tools = ./workspace/TOOLS.md;
      identity = ./workspace/IDENTITY.md;
      user = ./workspace/USER.md;
    };

    bundledPlugins = {
      # nix-openclaw 把 skill 目录直接当 extraDirs（loader 找 <dir>/skills），
      # 开着会持续报 FsSafeError。
      summarize.enable = false;
      goplaces.enable = false;
    };

    # 两个搜索 provider 都装，实际用哪个由下面的 tools.web.search.provider 决定。
    runtimePlugins = [
      "exa"
      "tavily"
    ];

    runtimePackages = [ pkgs.gh ];

    config = {
      gateway = {
        mode = "local";
        bind = "loopback";
        auth.mode = "token";
        # nginx 在回环上转发，不信任它会被判为"代理形状"流量并 403。
        trustedProxies = [ "127.0.0.1" ];
        controlUi.allowedOrigins = [ "https://claw.liyinuo.tech" ];
        nodes.commands.allow = [ "camera.snap" ];
      };

      channels.telegram = {
        dmPolicy = "allowlist";
        allowFrom = [ 8706786498 ];
        groups."*".requireMention = true;
      };

      commands.ownerAllowFrom = [ "telegram:8706786498" ];

      tools.web.search.provider = "tavily";

      # 内置记忆（memory-core）接 Cloudflare Workers AI 做 embedding，没有第二套。
      # embedding 的 provider/model/sources 是索引身份的一部分，改了要
      # `openclaw memory index --force` 重建索引。
      memory.search = {
        enabled = true;
        provider = "openai-compatible";
        model = "@cf/qwen/qwen3-embedding-0.6b";
        remote.baseUrl = "https://api.cloudflare.com/client/v4/accounts/c6f9a27ce7ae62bb8971fde57e40a28c/ai/v1";
        # 只写 sources 不够：cross-conversation recall 会自动把 sessions 加进来，
        # 关掉它免得 transcript worker 吃内存。
        sources = [ "memory" ];
        rememberAcrossConversations = false;

        # 默认 unicode61 会把一串汉字当一个 token，对中文关键词检索等于失效；
        # 改 trigram 后中文子串可匹配，代价是索引略大、英文词边界丢失（语义由向量兜底）。
        store.fts.tokenizer = "trigram";
      };

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
      plugins.entries."active-memory".enabled = true;

      browser.enabled = false;

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

      # 用内置的 OpenCode Go provider。上下文钉成 1000K（Go 目录默认按 200K）。
      # compat.supportedReasoningEfforts 必须配 reasoning = true：只写档位时 configured
      # 行被当成非推理模型，档位会塌成 off + ultra。
      models.providers.opencode-go.models = [
        {
          id = "deepseek-v4.1-flash";
          name = "DeepSeek V4.1 Flash";
          reasoning = true;
          contextTokens = 1000000;
          maxTokens = 384000;
          input = [
            "text"
            "image"
          ];
          compat = {
            supportsReasoningEffort = true;
            supportedReasoningEfforts = [
              "low"
              "high"
              "max"
            ];
          };
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
      agents.defaults.model.primary = "opencode-go/deepseek-v4.1-flash";
      agents.defaults.utilityModel = "opencode-go/longcat-2.5-preview-free";
    };
  };

  # nix-openclaw 生成的单元没有 [Install] 段，不补就不会开机自启。
  systemd.user.services."openclaw-gateway".Install.WantedBy = [ "default.target" ];

  # 上游早已不读 TOOLS.md，但 nix-openclaw 每次激活都物化它并追加清单，
  # 所以在物化之后删掉。上游让 tools 可选后可以去掉这段。
  home.activation.openclawDropRetiredToolsMd =
    lib.hm.dag.entryAfter [ "openclawWorkspaceFiles" ] ''
      rm -f ${lib.escapeShellArg "${config.programs.openclaw.workspaceDir}/TOOLS.md"}
    '';
}
