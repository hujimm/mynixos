# ============================================================================
# 【已弃用 · 2026-10-18】lightclaw 侧：Honcho 记忆插件的"自建打包"（仅存档）
# ============================================================================
#
# 这是当时给 OpenClaw 装官方 Honcho 记忆插件（npm 包 @honcho-ai/openclaw-honcho）
# 用的那段 Nix：因为 nix-openclaw 的标准入口走不通，我们改用手打包插件 root +
# plugins.load.paths 接入。最终决定不再用 Honcho（记忆交给内置 memory-core），
# 所以整段摘出构建、只留档。服务端（aliyun 上的 Honcho）见
# modules/_trash/nixos/honcho.nix。
#
# ---------------------------------------------------------------------------
# 【为什么当时不能用 nix-openclaw 的标准入口 runtimePluginSources】
#   1) 依赖证据：插件的构建校验（nix-openclaw 的 scripts/runtime-plugin/install.mjs）
#      要求插件自带 bundled node_modules 或 npm-shrinkwrap.json；而 honcho 的发布物
#      两者都没有（它的依赖靠安装时 npm 现场解析，而 nix-openclaw 禁止构建期跑包管理器）。
#      ClawHub 上的那份产物也是同一个 tarball（46 文件、无 node_modules），一样过不了。
#   2) 入口字段：honcho 把入口写在 package.json 的 `openclaw.extensions`，
#      而 install.mjs 读的是 `runtimeExtensions` → 还会再报 "no runtime entry"。
#   所以只能自己物化依赖并组装出 OpenClaw 认可的插件 root（= 复刻 install.mjs 的形状）。
#
# ---------------------------------------------------------------------------
# 【恢复步骤】
#   1) 在 hosts/lightclaw/openclaw.nix 的 `let` 里加：
#        honchoPlugin = import ../../modules/_trash/hm/openclaw-honcho-plugin.nix { inherit pkgs; };
#      （或把下面整段 let 粘回去）
#   2) 因为要同时用原始 plugins.load.paths，**必须把 exa/tavily 也从 runtimePlugins
#      改成原始路径**——nix-openclaw 断言：runtimePlugins/runtimePluginSources 与原始
#      load.paths 在同一实例里互斥。config 大致是：
#        plugins.load.paths = [
#          "${pkgs.openclawRuntimePlugins.exa}"
#          "${pkgs.openclawRuntimePlugins.tavily}"
#          "${honchoPlugin}"
#        ];
#        plugins.entries = {
#          exa.enabled = true;  tavily.enabled = true;
#          "openclaw-honcho" = {
#            enabled = true;
#            hooks.allowConversationAccess = true;   # ★ 必需，否则不存任何消息
#            config = {
#              baseUrl = "http://10.144.144.1:8010";  # aliyun，经 EasyTier；自建免 apiKey
#              workspaceId = "openclaw";
#              # honcho_ask 慢时可加 timeoutMs
#            };
#          };
#        };
#        plugins.allow = [ ... "exa" "tavily" "openclaw-honcho" ... ];  # 原始路径不再自动追加
#   3) 升级插件：改 honchoVersion → 重建；两个 hash 都要重取。
#        - tarball 的 hash（fetchurl）可手算：npm tarball 的 sha256 → SRI
#        - honchoDeps 的 outputHash（recursive NAR）只能构建一次、读报错里的真值填回
#   4) 迁移（官方 `openclaw honcho setup` 在 Nix mode 走不通！）：
#      它的代码顺序是"先写 ~/.openclaw/openclaw.json，再上传旧记忆文件"，
#      而 Nix mode 下该文件是 nix store 只读软链 → 命令在迁移之前就失败了。所以：
#        a) seed 上传要自己做：建一次会话 `migration-setup`，加 peers
#           （owner: observeMe=true/observeOthers=false；agent-main: true/true），
#           再对每个文件 uploadFile：USER.md → owner peer；
#           SOUL/IDENTITY/AGENTS/TOOLS/BOOTSTRAP/MEMORY.md + memory/、canvas/ → agent peer。
#        b) 还要把插件自带 workspace 模板（包内 workspace_md/AGENTS.md、SOUL.md、
#           BOOTSTRAP.md）里"记忆一律用 honcho_* 工具"的指引，手工并进
#           hosts/lightclaw/workspace/AGENTS.md 等 Nix 源文件——否则 agent 有工具但不用。
#   5) 迁移时的持续成本/延迟提醒：deriver 有批处理门控（短消息最长 30 分钟才推导出
#      "结论/画像"，消息本身即时落库）；画像在服务端、不可审计；依赖 aliyun 在线。
#
# 说明：内置记忆（memory-core）走 Cloudflare Workers AI 做 embedding 的配置**不在**这里，
# 它保留在 hosts/lightclaw/openclaw.nix 的 memory.search（与 Honcho 无关）。
# ============================================================================

{ pkgs, lib ? pkgs.lib }:

let
  # 必须是 gateway 包：overlay 里 pkgs.openclaw 只是薄包装，
  # 而插件 peer 一律链到 ${gateway}/lib/openclaw（同 nix-openclaw）。
  gatewayPkg = pkgs.openclaw-gateway;
  honchoVersion = "1.7.0";

  # 官方 npm tarball（hash = 该 tarball 的 sha256-SRI）。
  honchoSrc = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@honcho-ai/openclaw-honcho/-/openclaw-honcho-${honchoVersion}.tgz";
    hash = "sha256-F1zkDsITr6j6armXJw02gZk+7CU122kOH1NOL4k3vgk=";
  };

  # 固定输出派生（FOD，允许联网）：物化生产依赖。输出按 hash 钉死 —— 上游依赖漂移
  # 会导致构建失败而不是静默变化。
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
      # --legacy-peer-deps：不解析/不拉 openclaw peer（运行时由下面的软链提供）
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
honchoPlugin
