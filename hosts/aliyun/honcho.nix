# aliyun 上的 Honcho 记忆服务（全声明式）。
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
  image = "ghcr.io/plastic-labs/honcho:latest";

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
    VECTOR_DIMENSIONS = 1024

    [embedding.model_config]
    transport = "openai"
    model = "${cfModel}"

    [embedding.model_config.overrides]
    base_url = "${cfBaseUrl}"
    api_key_env = "CF_EMBEDDING_API_KEY"

  ''
  + lib.concatMapStrings chatBlock chatSections;

  # api 的入口：官方 entrypoint 只是 迁移 + fastapi（8000），这里改为 8010。
  apiEntry = pkgs.writeShellScriptBin "honcho-api-entry" ''
    set -e
    /app/.venv/bin/python scripts/provision_db.py
    exec /app/.venv/bin/fastapi run --host 0.0.0.0 --port ${toString honchoPort} --workers "''${API_WORKERS:-1}" src/main.py
  '';

  envFile = config.sops.templates."honcho-env".path;
in
{
  # ---- 容器运行时 ----
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # ---- Postgres（原生）+ pgvector ----
  services.postgresql = {
    enable = true;
    extensions = ps: [
      ps.pgvector
      ps.pg_trgm
    ];
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
      psql -h /run/postgresql -d postgres -c "ALTER ROLE honcho WITH PASSWORD '$(cat ${config.sops.secrets."honcho-db-password".path})'"
      psql -h /run/postgresql -d honcho -c "CREATE EXTENSION IF NOT EXISTS vector"
      psql -h /run/postgresql -d honcho -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
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
      entrypoint = [ "${apiEntry}/bin/honcho-api-entry" ];
      environmentFiles = [ envFile ];
      volumes = [
        "/etc/honcho/config.toml:/app/config.toml:ro"
        "${apiEntry}/bin/honcho-api-entry:/usr/local/bin/honcho-api-entry:ro"
      ];
      extraOptions = [ "--network=host" ];
    };
    honcho-deriver = {
      image = image;
      entrypoint = [ "/app/.venv/bin/python" ];
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
  systemd.services.podman-honcho-api = {
    after = [
      "postgresql.service"
      "honcho-db-setup.service"
    ];
    requires = [ "honcho-db-setup.service" ];
  };

  # ---- 防火墙：只对 EasyTier 网卡放行 ----
  networking.firewall.interfaces."tun0".allowedTCPPorts = [ honchoPort ];
}
