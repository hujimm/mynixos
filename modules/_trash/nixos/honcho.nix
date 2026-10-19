# ============================================================================
# 【已弃用 · 2026-10-18】aliyun 上的 Honcho 自建记忆服务（整份模块，仅存档）
# ============================================================================
#
# 状态：已停用，从构建中摘除。文件保留在这里只为"以后想恢复"时有个准确的起点。
#
# 为什么停用：
#   最终判断是"记忆用 agent 自带的那套就够了，不要第二套系统"。
#   内置那套（workspace Markdown + SQLite 混合检索 + dreaming 巩固 + provenance 防注入）
#   本身很完善，而且 Honcho 只收对话消息、看不到 workspace 文件；两套并存等于
#   重复注入 + 双份用户画像 + 额外内存开销（这台机器 RSS 已 1.5-1.6GiB）。
#
# ---------------------------------------------------------------------------
# 【恢复步骤】按顺序做，每步都有坑，别跳
# ---------------------------------------------------------------------------
#   1) 把本文件移回 hosts/aliyun/honcho.nix：
#        git mv modules/_trash/nixos/honcho.nix hosts/aliyun/honcho.nix
#   2) hosts/aliyun/default.nix 的 imports 里加回：  ./honcho.nix
#   3) 密钥：本模块用 secrets/honcho.yaml 里的三个键
#        honcho-db-password / honcho-opencode-api-key / honcho-cloudflare-api-token
#      该文件的 sops 规则在 modules/nixos/security/.sops.yaml（接收者 orion + aliyun）。
#      若这条规则被删过，先加回来再 `sops updatekeys`，否则 aliyun 解不开 → 容器起不来。
#   4) 本机（桌面）留一个 GC root，否则 nightly `nix.gc` 会把只属于 aliyun 的闭包回收，
#      下次重建又得重编：
#        nix build .#nixosConfigurations.aliyun.config.system.build.toplevel -o ~/nixos-aliyun
#   5) 切换：  nixos-rebuild switch --flake .#aliyun --target-host aliyun-ecs
#      （首次要拉 416MB 镜像 + 跑 DB 迁移，8010 要等 2-3 分钟才监听）
#   6) 验证清单：
#        systemctl is-active postgresql honcho-db-setup podman-honcho-api podman-honcho-deriver
#        podman ps                       # honcho-api / honcho-deriver 都 Up
#        ss -lntp | grep 8010            # fastapi 在听
#        curl -s http://10.144.144.1:8010/health      # {"status":"ok"}
#        sudo -u postgres <pg>/bin/psql -d honcho -c '\dx'   # 要有 vector + pg_trgm
#        sudo -u postgres <pg>/bin/psql -d honcho -c 'select version_num from alembic_version'
#      公网必须**不可达**（防火墙只放 tun0），从网格内其它机器经 EasyTier 必须可达。
#
# ---------------------------------------------------------------------------
# 【当时踩过的坑 · 恢复时别重踩】
# ---------------------------------------------------------------------------
#   - honcho-db-setup 里不能写裸 `psql`（PATH 里没有），要用
#     `${config.services.postgresql.package}/bin/psql` 绝对路径。
#   - 容器的 entrypoint 不能用宿主机 nix store 路径（容器里不存在），也不能用
#     writeShellScriptBin（shebang 指向 nix 的 bash，镜像里没有）；要用镜像自带的
#     `/bin/sh -c '<脚本>'`。
#   - 维度：迁移只建默认 vector(1536)。真正决定库列维度的是**环境变量**
#     EMBEDDING_VECTOR_DIMENSIONS（env 优先于 config.toml，迁移脚本只读 env）。
#     官方 bootstrap 是三步：alembic 迁移 → `scripts/configure_embeddings.py --yes`
#     （ALTER 成目标维度）→ 起 API/deriver。我们把第 2 步并进了 api 的启动脚本。
#     列维度不对时 deriver 会以 StartupValidationError 拒绝启动（api 会崩溃重启循环）。
#   - 镜像必须钉 digest（曾用 :latest，后来发现上游 v3.3.0 反而比 latest 旧）。
#   - 该镜像允许的推断：不设 cache（`[cache] ENABLED=false`，无 Redis）；
#     deriver 的 representation 有批处理门控，短消息最长 30 分钟才被推导
#     （REPRESENTATION_BATCH_MAX_AGE_SECONDS=1800），消息本身是即时落库的。
#   - 端口用 8010：aliyun 的 mcp-nixos 已占 10.144.144.1:8000。
# ============================================================================
#
# 组件：podman + oci-containers(api / deriver) + 原生 Postgres(pgvector)；不开 Redis。
# 网络：绑 EasyTier 网卡（10.144.144.1），无认证，防火墙只对 tun0 放行 → 依赖覆盖网隔离。
# 端口用 8010：aliyun 的 mcp-nixos 已占 10.144.144.1:8000。
#
# chat 走 opencode-go（必须带 x-opencode-session 头，见 config.toml）；
# embedding 走 Cloudflare Workers AI（qwen3-embedding-0.6b，1024 维）。
{ config, pkgs, lib, ... }:

let
  honchoPort = 8010;
  # 镜像钉死为已实测通过的那份，不用 :latest（否则以后某次重建悄悄换版本，
  # config.toml 的 schema 不匹配会静默崩）。这份 digest = 2026-10-16 的 :latest，
  # rev ed9fe6c，是上游 v3.3.0 之后的 main 构建。升级时手动改这里的 digest。
  image = "ghcr.io/plastic-labs/honcho@sha256:50cc57c327210a694b3934fe8c3c090fca5b5f0271fe911e6a15ddc752928657";

  ocBaseUrl = "https://opencode.ai/inference/go/openai/v1";
  ocModel = "deepseek-v4.1-flash";
  # 静态会话头（32 位 hex）。见方案讨论：OpenCode 只强制"该头存在"。
  ocSession = "bf0aebba43ea6b71cfec8895d8f3b9db";

  cfBaseUrl = "https://api.cloudflare.com/client/v4/accounts/c6f9a27ce7ae62bb8971fde57e40a28c/ai/v1";
  cfModel = "@cf/qwen/qwen3-embedding-0.6b";

  # 每个 chat 模块：openai transport + opencode-go 端点 + 必需的头
  chatBlock =
    section: ''
      [${section}.model_config]
      transport = "openai"
      model = "${ocModel}"

      [${section}.model_config.overrides]
      base_url = "${ocBaseUrl}"

      [${section}.model_config.overrides.provider_params.extra_headers]
      User-Agent = "honcho/1.0"
      x-opencode-session = "${ocSession}"
    '';
  chatSections = [
    "deriver"
    "dialectic.levels.minimal"
    "dialectic.levels.low"
    "dialectic.levels.medium"
    "dialectic.levels.high"
    "dialectic.levels.max"
    "summary"
    "dream.deduction_model_config"
    "dream.induction_model_config"
  ];

  configToml = ''
    [cache]
    ENABLED = false

    [vector_store]
    TYPE = "pgvector"

    [embedding]
    # 注意：真正决定库列维度的是环境变量 EMBEDDING_VECTOR_DIMENSIONS
    # （见 honcho-env 模板）；迁移脚本只读 env，这里的值须与之保持一致。
    VECTOR_DIMENSIONS = 1024

    [embedding.model_config]
    transport = "openai"
    model = "${cfModel}"

    [embedding.model_config.overrides]
    base_url = "${cfBaseUrl}"
    api_key_env = "CF_EMBEDDING_API_KEY"

  ''
  + lib.concatMapStrings chatBlock chatSections;

  # api 入口：镜像自带 /bin/sh，依次跑"迁移 + 维度校准 + fastapi(8010)"。
  # 不用 writeShellScriptBin——它的 shebang 指向 nix 的 bash，镜像里没有。
  apiCmd = [
    "-c"
    ''
      set -e
      /app/.venv/bin/python scripts/provision_db.py
      # 官方 bootstrap 第 2 步：迁移只建默认 vector(1536)，须 ALTER 成目标维度
      # （EMBEDDING_VECTOR_DIMENSIONS=1024）。维度已一致时是 no-op。
      /app/.venv/bin/python scripts/configure_embeddings.py --yes
      exec /app/.venv/bin/fastapi run --host 0.0.0.0 --port ${toString honchoPort} --workers "''${API_WORKERS:-1}" src/main.py
    ''
  ];

  envFile = config.sops.templates."honcho-env".path;
in
{
  # ---- 容器运行时 ----
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # ---- Postgres（原生）+ pgvector ----
  services.postgresql = {
    enable = true;
    extensions = ps: [ ps.pgvector ];
    ensureDatabases = [ "honcho" ];
    ensureUsers = [
      {
        name = "honcho";
        ensureDBOwnership = true;
      }
    ];
    authentication = ''
      local all all peer
      host all all 127.0.0.1/32 scram-sha-256
      host all all ::1/128 scram-sha-256
    '';
  };

  # honcho 角色密码 + 两个扩展（= 官方 database/init.sql）。
  systemd.services.honcho-db-setup = {
    description = "Honcho: set DB role password and create extensions";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
    };
    script = ''
      set -e
      psql=${config.services.postgresql.package}/bin/psql
      $psql -h /run/postgresql -d postgres -c "ALTER ROLE honcho WITH PASSWORD '$(cat ${config.sops.secrets."honcho-db-password".path})'"
      $psql -h /run/postgresql -d honcho -c "CREATE EXTENSION IF NOT EXISTS vector"
      $psql -h /run/postgresql -d honcho -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
    '';
  };

  # ---- 非密配置：config.toml（挂进容器）----
  environment.etc."honcho/config.toml" = {
    text = configToml;
    mode = "0444";
  };

  # ---- 密钥（sops）----
  sops.secrets."honcho-db-password" = {
    sopsFile = ../../modules/nixos/security/secrets/honcho.yaml;
    owner = "postgres";
    mode = "0400";
  };
  sops.templates."honcho-env" = {
    content = ''
      LLM_OPENAI_API_KEY=${config.sops.placeholder."honcho-opencode-api-key"}
      CF_EMBEDDING_API_KEY=${config.sops.placeholder."honcho-cloudflare-api-token"}
      DB_CONNECTION_URI=postgresql+psycopg://honcho:${config.sops.placeholder."honcho-db-password"}@127.0.0.1:5432/honcho
      API_WORKERS=1
      # 环境变量优先于 config.toml；迁移脚本读的是这个（否则按默认 1536 建列）。
      EMBEDDING_VECTOR_DIMENSIONS=1024
    '';
    mode = "0400";
  };
  # 供上述 template 引用的两个密钥也在此声明（同一文件）。
  sops.secrets."honcho-opencode-api-key".sopsFile = ../../modules/nixos/security/secrets/honcho.yaml;
  sops.secrets."honcho-cloudflare-api-token".sopsFile = ../../modules/nixos/security/secrets/honcho.yaml;

  # ---- Honcho 容器 ----
  virtualisation.oci-containers.containers = {
    honcho-api = {
      image = image;
      entrypoint = "/bin/sh";
      cmd = apiCmd;
      environmentFiles = [ envFile ];
      volumes = [ "/etc/honcho/config.toml:/app/config.toml:ro" ];
      extraOptions = [ "--network=host" ];
    };
    honcho-deriver = {
      image = image;
      entrypoint = "/app/.venv/bin/python";
      cmd = [
        "-m"
        "src.deriver"
      ];
      environmentFiles = [ envFile ];
      volumes = [ "/etc/honcho/config.toml:/app/config.toml:ro" ];
      extraOptions = [ "--network=host" ];
      dependsOn = [ "honcho-api" ];
    };
  };

  # 等 Postgres 与建库完成再起容器（oci-containers 的 dependsOn 只串容器）。
  # 同时给两个容器在 cgroup 层加内存兜底：实测各约 220MB，768M 上限足够，
  # 万一哪天异常尖峰也只 OOM 自己、不拖垮 1.8G 的本机（含 Postgres）。
  systemd.services.podman-honcho-api = {
    after = [
      "postgresql.service"
      "honcho-db-setup.service"
    ];
    requires = [ "honcho-db-setup.service" ];
    serviceConfig = {
      MemoryHigh = "512M";
      MemoryMax = "768M";
    };
  };
  systemd.services.podman-honcho-deriver.serviceConfig = {
    MemoryHigh = "512M";
    MemoryMax = "768M";
  };

  # ---- 防火墙：只对 EasyTier 网卡放行 ----
  networking.firewall.interfaces."tun0".allowedTCPPorts = [ honchoPort ];
}
