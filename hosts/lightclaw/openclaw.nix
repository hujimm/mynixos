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

    # 内置工具插件：summarize（总结网页/PDF/视频）开启；
    # goplaces 出厂默认就是开的，这里显式关掉（不用 Google Places）。
    bundledPlugins = {
      summarize.enable = true;
      goplaces.enable = false;
    };

    # 运行时插件：联网搜索的两个 provider（exa / tavily）。
    # 两个都装好；实际用哪个由下面 config.tools.web.search.provider 决定。
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

      # 模型：用 OpenClaw **内置**的 OpenCode Go provider，ref = "opencode-go/<模型id>"，
      # 无需自定义 provider；凭证走上面的 OPENCODE_API_KEY。
      # 主模型：对话与 agent 工作。
      agents.defaults.model.primary = "opencode-go/deepseek-v4.1-flash";
      # 辅助模型：标题生成、摘要、进度叙述等短任务。
      # 注：hermes 用的 cat-jam-free 不在 OpenCode Go 目录里（实测 --all 也没有），
      # 改用同样便宜的 flash 模型。
      agents.defaults.utilityModel = "opencode-go/glm-5.3-flash";
    };
  };

  # nix-openclaw 生成的 systemd 用户单元没有 [Install] 段，默认不会被 enable，
  # 所以开机不会自启。这里补上 WantedBy，让它在 linger 下随 default.target 启动。
  systemd.user.services."openclaw-gateway".Install.WantedBy = [ "default.target" ];
}
