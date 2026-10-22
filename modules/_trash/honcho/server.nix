# Honcho 自建记忆服务（2026-10 弃用）。podman 跑 api / deriver 两个容器 + 原生
# Postgres(pgvector)，不开 Redis；绑 EasyTier 网卡，无认证，靠防火墙只放 tun0 隔离。
# 配套的 HM 插件在同级 plugin.nix。
{ config, pkgs, lib, ... }:

let
  # mcp-nixos 占了 8000。
  honchoPort = 8010;
  # 钉 digest 不用 :latest：上游 v3.3.0 反而比当时的 latest 旧。
  image = "ghcr.io/plastic-labs/honcho@sha256:50cc57c327210a694b3934fe8c3c090fca5b5f0271fe911e6a15ddc752928657";

  ocBaseUrl = "https://opencode.ai/inference/go/openai/v1";
  ocModel = "deepseek-v4.1-flash";
  # OpenCode 只强制该头存在。
  ocSession = "bf0aebba43ea6b71cfec8895d8f3b9db";

  cfBaseUrl = "https://api.cloudflare.com/client/v4/accounts/c6f9a27ce7ae62bb8971fde57e40a28c/ai/v1";
  cfModel = "@cf/qwen/qwen3-embedding-0.6b";

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
    # 真正决定库列维度的是环境变量 EMBEDDING_VECTOR_DIMENSIONS，迁移脚本只读 env，
    # 这里的值只须与之保持一致。
    VECTOR_DIMENSIONS = 1024

    [embedding.model_config]
    transport = "openai"
    model = "${cfModel}"

    [embedding.model_config.overrides]
    base_url = "${cfBaseUrl}"

  ''
  + lib.concatMapStrings chatBlock chatSections;

  # 镜像自带 /bin/sh；不能用 writeShellScriptBin（shebang 指向 nix 的 bash，镜像里没有）。
  apiCmd = [
    "-c"
    ''
      set -e
      /app/.venv/bin/python scripts/provision_db.py
      # 迁移只建默认 vector(1536)，官方 bootstrap 的第二步是 ALTER 到目标维度；一致时 no-op。
      /app/.venv/bin/python scripts/configure_embeddings.py --yes
      exec /app/.venv/bin/fastapi run --host 0.0.0.0 --port ${toString honchoPort} --workers "''${API_WORKERS:-1}" src/main.py
    ''
  ];

  env = {
    API_WORKERS = "1";
    EMBEDDING_VECTOR_DIMENSIONS = "1024";
  };
in
{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

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

  systemd.services.honcho-db-setup = {
    description = "Honcho: create extensions";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
    };
    # 裸 psql 不在 PATH 里，必须用 config 里的绝对路径。
    script = ''
      set -e
      psql=${config.services.postgresql.package}/bin/psql
      $psql -h /run/postgresql -d honcho -c "CREATE EXTENSION IF NOT EXISTS vector"
      $psql -h /run/postgresql -d honcho -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
    '';
  };

  environment.etc."honcho/config.toml" = {
    text = configToml;
    mode = "0444";
  };

  virtualisation.oci-containers.containers = {
    honcho-api = {
      inherit image;
      entrypoint = "/bin/sh";
      cmd = apiCmd;
      inherit env;
      volumes = [ "/etc/honcho/config.toml:/app/config.toml:ro" ];
      extraOptions = [ "--network=host" ];
    };
    honcho-deriver = {
      inherit image env;
      entrypoint = "/app/.venv/bin/python";
      cmd = [
        "-m"
        "src.deriver"
      ];
      volumes = [ "/etc/honcho/config.toml:/app/config.toml:ro" ];
      extraOptions = [ "--network=host" ];
      dependsOn = [ "honcho-api" ];
    };
  };

  # oci-containers 的 dependsOn 只串容器，这里等 Postgres 与建库。
  systemd.services.podman-honcho-api = {
    after = [
      "postgresql.service"
      "honcho-db-setup.service"
    ];
    requires = [ "honcho-db-setup.service" ];
    # 实测各约 220MB；上限只让异常尖峰 OOM 自己。
    serviceConfig = {
      MemoryHigh = "512M";
      MemoryMax = "768M";
    };
  };
  systemd.services.podman-honcho-deriver.serviceConfig = {
    MemoryHigh = "512M";
    MemoryMax = "768M";
  };

  networking.firewall.interfaces."tun0".allowedTCPPorts = [ honchoPort ];
}
