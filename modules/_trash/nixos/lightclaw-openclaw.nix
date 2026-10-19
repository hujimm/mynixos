# ============================================================================
# 【已弃用 · 2026-10-19】lightclaw 上的 OpenClaw 网关（整份 Home Manager 模块，仅存档）
# ============================================================================
#
# 状态：已停用、从构建中摘除。保留在此只为"以后想恢复"时有个准确起点。
#
# 为什么停用：主人只当玩一下，不再用 OpenClaw。一并归档的相关件：
#   - modules/_trash/nixos/lightclaw-nginx.nix（claw.liyinuo.tech 的 WSS 反代）
#   - modules/_trash/nixos/lightclaw-workspace/（AGENTS/SOUL/IDENTITY/USER/TOOLS.md）
#   - modules/_trash/nixos/openclaw-desktop.nix（桌面笔记本上的官方 Linux 桌面端包）
#   - modules/_trash/hm/openclaw-honcho-plugin.nix（更早弃用的 Honcho 插件）
#
# ---------------------------------------------------------------------------
# 【恢复步骤】按顺序做
# ---------------------------------------------------------------------------
#   1) 文件搬回：  git mv modules/_trash/nixos/lightclaw-openclaw.nix hosts/lightclaw/openclaw.nix
#                  git mv modules/_trash/nixos/lightclaw-nginx.nix      hosts/lightclaw/nginx.nix
#                  git mv modules/_trash/nixos/lightclaw-workspace    hosts/lightclaw/workspace
#   2) flake.nix 加回输入（lightclaw 的 HM 模块与 overlay 都靠它）：
#        nix-openclaw = {
#          url = "github:openclaw/nix-openclaw";
#          inputs.nixpkgs.follows = "nixpkgs";
#          inputs.home-manager.follows = "home-manager";
#        };
#   3) flake.nix 的 lightclaw 配置 modules 里加回： home-manager.nixosModules.home-manager
#   4) hosts/lightclaw/default.nix 加回：imports 里的 ./nginx.nix、
#      nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];、
#      users.users.openclaw（linger）+ 免密 sudo、home-manager.* 那几行（见下"归档时的差异"）
#   5) hosts/lightclaw/sops.nix 加回 openclaw-* 那些 sops.secrets 声明
#      （密钥在 secrets/openclaw.yaml；规则在 modules/nixos/security/.sops.yaml）
#   6) 重建：  nixos-rebuild switch --flake .#lightclaw --target-host lightclaw
#      验证：    sudo -u openclaw -i systemctl --user status openclaw-gateway
#                curl -sk --resolve claw.liyinuo.tech:443:127.0.0.1 https://claw.liyinuo.tech/
#
# 归档时的差异（default.nix 里被摘掉的那几行）：
#   nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];
#   users.users.openclaw = { isNormalUser = true; home = "/home/openclaw"; linger = true; };
#   security.sudo.extraRules = [{ users = [ "openclaw" ]; commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }]; }];
#   home-manager.useGlobalPkgs = true;
#   home-manager.useUserPackages = true;
#   home-manager.sharedModules = [ inputs.nix-openclaw.homeManagerModules.openclaw ];
#   home-manager.users.openclaw = ./openclaw.nix;
#
# 运行时残留（重建后服务即消失，数据不会自动删）：
#   /home/openclaw/（含 ~/.openclaw 配置、会话 SQLite、记忆库）、用户 openclaw 本身
#   清理：sudo userdel -r openclaw
#
# ---------------------------------------------------------------------------
# 以下是停用前的原始内容
# ---------------------------------------------------------------------------
#
# OpenClaw 网关（lightclaw）。Home Manager 模块，运行在 openclaw 用户下。
#
# 形态：systemd 用户服务 openclaw-gateway（linger 已开，开机自启）。
# 权限：默认即 OpenClaw 官方的"单信任域"姿态（exec 无审批）；命令以 openclaw 用户执行，
#       该用户有免密 sudo，故 agent 需要时可提权。
# 入口：网关只绑回环；外网经 nginx(443, Cloudflare Origin CA 证书, claw.liyinuo.tech) 反代，
# 证书/私钥走 sops（见 ./nginx.nix 与 ./sops.nix）。
{ osConfig, config, pkgs, lib, ... }:

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
    #
    # 注意两件与上游有关的实情（2026.10.4）：
    #  1) 真正组成会话 prompt 的只有 AGENTS.md / SOUL.md / IDENTITY.md / USER.md
    #     （上游 workspace-bootstrap-policy 的 GENERATED_WORKSPACE_BOOTSTRAP_FILENAMES）。
    #     **TOOLS.md 已被上游废弃**：运行时不再读它，本地工具约定的正式位置是 AGENTS.md 的
    #     `## Tools` 段（上游有 doctor-tools-md-migration 负责搬过去）。我们本机的工具约定
    #     已并入 AGENTS.md。
    #     但 nix-openclaw（当前 rev）还没跟上：`bootstrapFiles.tools` 是**必填**（无 default），
    #     而且总会往 TOOLS.md 追加"Nix-managed tools"清单 → 声明层面删不掉、也无法让它为空。
    #     所以下面的 activation 在物化之后把它删掉，让工作区里不留这个死文件
    #     （TOOLS.md 源文件本身留作占位说明；将来 nix-openclaw 把 tools 改成可选，就删掉那段 activation）。
    #  2) 官方出厂模板（含"记忆分工/行为红线/主动性"等规则）只在**全新工作区** seed 一次；
    #     我们接管工作区后就拿不到它们了，所以把其中对本机适用的部分手写进了 AGENTS.md。
    workspace.bootstrapFiles = {
      agents = ./workspace/AGENTS.md;
      soul = ./workspace/SOUL.md;
      tools = ./workspace/TOOLS.md; # 上游已废弃（不被读取）；内容已并入 AGENTS.md 的 Tools 段
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
        # 只绑回环：外网访问走 nginx(443, Cloudflare Origin CA 证书) → 127.0.0.1:18789，
        # 见 hosts/lightclaw/nginx.nix。这样网关本身不直接暴露。
        bind = "loopback";
        auth.mode = "token"; # token 值来自 OPENCLAW_GATEWAY_TOKEN
        # nginx 在回环上转发（带 X-Real-IP / X-Forwarded-*），必须显式信任它这一个来源，
        # 否则网关把这种"代理形状"的流量判为不可信并返回 403（网关日志会提示这句）。
        trustedProxies = [ "127.0.0.1" ];
        # 浏览器访问 Control UI 时的来源白名单（网关只为 loopback 播了默认值）。
        controlUi.allowedOrigins = [ "https://claw.liyinuo.tech" ];
        # 节点（手机）危险/隐私命令白名单：默认不带，需显式 opt-in。
        # camera.snap = 手机拍照（reminders.add 这台手机的 App 未实现，故不加）。
        nodes.commands.allow = [ "camera.snap" ];
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

        # CJK 分词：默认 unicode61 会把一串汉字整体当一个 token → 关键词那半对中文等于失效
        # （我们 USER.md/记忆都是中文）。trigram 是 OpenClaw schema 官方暴露的取值
        # （enum: unicode61 | trigram），SQLite 3.53 实测可用：改成 3 字符滑窗后中文子串可匹配。
        # 代价：索引略大、英文词边界语义丢失（语义那半由向量兜底）。改了要重建索引。
        store.fts.tokenizer = "trigram";
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
      #
      # compat.supportedReasoningEfforts 显式钉死推理档位：上游/插件声明的
      # ["low" "high" "max"] 在 OpenClaw 的 thinking profile 推导里会被退化成
      # 只剩 off/ultra（菜单与校验不一致）。必须同时写 reasoning = true，
      # 否则 configured 行被当成非推理模型，档位塌成 off + ultra（harness 档）。
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
      # 主模型：对话与 agent 工作。
      agents.defaults.model.primary = "opencode-go/deepseek-v4.1-flash";
      # 辅助模型：标题生成、摘要、进度叙述等短任务。
      agents.defaults.utilityModel = "opencode-go/longcat-2.5-preview-free";
    };
  };

  # nix-openclaw 生成的 systemd 用户单元没有 [Install] 段，默认不会被 enable，
  # 所以开机不会自启。这里补上 WantedBy，让它在 linger 下随 default.target 启动。
  systemd.user.services."openclaw-gateway".Install.WantedBy = [ "default.target" ];

  # 上游把 TOOLS.md 废弃了（运行时不再读），但 nix-openclaw 的 `bootstrapFiles.tools` 是必填、
  # 且每次激活都会把它物化出来并追加"Nix-managed tools"清单 → 物化之后直接删掉，
  # 让工作区里不留这个死文件。将来 nix-openclaw 让 `tools` 可选时，删掉这段。
  home.activation.openclawDropRetiredToolsMd =
    lib.hm.dag.entryAfter [ "openclawWorkspaceFiles" ] ''
      rm -f ${lib.escapeShellArg "${config.programs.openclaw.workspaceDir}/TOOLS.md"}
    '';
}
