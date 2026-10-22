# Hindsight：自托管 Agent 记忆服务（2026-10 弃用）。LLM / Embedding / Reranker 全走外部
# API（slim 镜像不含本地模型），数据库用同机 pgvector 容器，配置全为 HINDSIGHT_API_* 环境变量。
#
# 8888 默认无鉴权，必须开 ApiKeyTenantExtension；容器端口只绑 127.0.0.1，对外由 nginx 终结 TLS。
{ ... }:

let
  apiDomain = "hindsight-api.liyinuo.tech";
  uiDomain = "hindsight.liyinuo.tech";
in
{
  virtualisation.oci-containers = {
    backend = "podman";

    containers = {
      hindsight-db = {
        image = "docker.io/pgvector/pgvector:pg18";
        # postgres 入口脚本会把 -c 参数透传给 postgres；按小内存机调参。
        cmd = [
          "-c"
          "shared_buffers=128MB"
          "-c"
          "max_connections=50"
        ];
        volumes = [ "/var/lib/hindsight/pgdata:/var/lib/postgresql/18/docker" ];
        extraOptions = [
          # 上限而非预留：实测常驻 ~150–250MB。
          "--memory=512m"
          # OOM 排序：比应用容器晚死，但早于 hermes。
          "--oom-score-adj=400"
          "--health-cmd=pg_isready -U hindsight -d hindsight_db"
          "--health-interval=15s"
          "--health-timeout=5s"
          "--health-retries=5"
          "--health-start-period=30s"
        ];
      };

      # standalone 版同一容器内跑 API(8888) 与 Control Plane(9999)。
      hindsight = {
        image = "ghcr.io/vectorize-io/hindsight:0.10.3-slim";
        dependsOn = [ "hindsight-db" ];
        environment = {
          TZ = "Asia/Shanghai";

          # LLM：OpenCode Go 内置 provider，必需的 x-opencode-session 头由 Hindsight 注入。
          HINDSIGHT_API_LLM_PROVIDER = "opencode-go";
          HINDSIGHT_API_LLM_MODEL = "cat-jam-free";
          # failover 顺序 [0] cat-jam-free → [1] deepseek-v4.1-flash；成员变量 n 从 1 连续。
          HINDSIGHT_API_LLM_1_PROVIDER = "opencode-go";
          HINDSIGHT_API_LLM_1_MODEL = "deepseek-v4.1-flash";
          HINDSIGHT_API_LLM_STRATEGY = builtins.toJSON { mode = "failover"; };

          # Embedding：Cloudflare 的 OpenAI 兼容口；qwen3-embedding-0.6b 原生 1024 维。
          HINDSIGHT_API_EMBEDDINGS_PROVIDER = "openai";
          HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL = "https://api.cloudflare.com/client/v4/accounts/c6f9a27ce7ae62bb8971fde57e40a28c/ai/v1";
          HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL = "@cf/qwen/qwen3-embedding-0.6b";
          # CF 侧输入上限 4096 token；Hindsight 按其分词器计数可能偏大，遇 400 再减半。
          HINDSIGHT_API_EMBEDDINGS_MAX_INPUT_TOKENS = "4096";

          # Qwen3-Embedding 是 instruction-aware：查询侧带前缀、文档侧裸文本，两者分开
          # 编码，所以加前缀不用重灌索引。实测 hit@1 70%→90%、MRR 0.850→0.942。
          # 结尾 "Query: " 后的空格不能省，改前缀等于换查询空间，门槛要重校。
          HINDSIGHT_API_EMBEDDINGS_QUERY_PREFIX = "Instruct: Given a web search query, retrieve relevant passages that answer the query\nQuery: ";

          # Reranker 用 NVIDIA NIM。Hindsight 的 reranker provider 是固定清单，NVIDIA 不在
          # 其中，所以经 LiteLLM SDK 桥接。
          # 不要设 HINDSIGHT_API_RERANKER_LITELLM_SDK_API_BASE：路径含 /retrieval/ 时 LiteLLM
          # 会原样使用，漏掉 /nvidia/<model>/reranking。留空即拼官方默认地址。
          # 此路不通的回退：HINDSIGHT_API_RERANKER_PROVIDER = "rrf"。
          HINDSIGHT_API_RERANKER_PROVIDER = "litellm-sdk";
          HINDSIGHT_API_RERANKER_LITELLM_SDK_MODEL = "nvidia_nim/nvidia/llama-nemotron-rerank-vl-1b-v2";

          HINDSIGHT_API_TENANT_EXTENSION = "hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension";

          # 官方整库导出接口默认关闭；开启后 POST /v1/default/banks/<id>/transfer/export
          # 可生成可导入的 ZIP（导入侧另需 ENABLE_DOCUMENT_IMPORT_API）。
          HINDSIGHT_API_ENABLE_DOCUMENT_EXPORT_API = "true";

          # 固定 worker id，避免容器重启后旧任务变孤儿。
          HINDSIGHT_API_WORKER_ID = "hindsight-lightsail";
          HINDSIGHT_API_HOST = "0.0.0.0";
          HINDSIGHT_API_LOG_LEVEL = "info";
          # 默认 0 = 永久保留，防数据库长期膨胀。
          HINDSIGHT_API_OPERATION_RETENTION_DAYS = "30";

          HINDSIGHT_CP_DATAPLANE_API_URL = "http://localhost:8888";

          # 近义结论合并门槛（默认 0.97）：同一 tag scope 内相似度到这个值才比较是否合并。
          # 0.97 太严，中文原句与英文摘要这类重复进不了比较，降到 0.9。
          HINDSIGHT_API_CONSOLIDATION_DEDUP_THRESHOLD = "0.9";
        };
        ports = [
          "127.0.0.1:8888:8888"
          "127.0.0.1:9999:9999"
        ];
        extraOptions = [
          # 上限而非预留：实测 API+CP 常驻 ~500–750MB。
          "--memory=1024m"
          # OOM 排序：内存见底时最先死，可自动重启、可降级。
          # 必须用 podman 的 --oom-score-adj：容器进程在 machine.slice/libpod-*.scope 里，
          # 不在 podman-<name>.service 的 cgroup 下，unit 上设的分传不到。
          "--oom-score-adj=600"
          # 给 API/CP 及 DB 连接收尾的时间（官方脚本建议 ≥30s）。
          "--stop-timeout=30"
          "--security-opt=no-new-privileges"
          # 镜像自带 python3 + hindsight_api.http_probe（与官方 start-all.sh 同款）。
          "--health-cmd=python3 -m hindsight_api.http_probe http://localhost:8888/health 5"
          "--health-interval=30s"
          "--health-timeout=10s"
          "--health-retries=5"
          "--health-start-period=180s"
        ];
      };
    };
  };

  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # PGDATA 需归镜像内的 postgres（uid/gid 999）。
  systemd.tmpfiles.rules = [
    "d /var/lib/hindsight 0755 root root -"
    "d /var/lib/hindsight/pgdata 0700 999 999 -"
  ];

  services.nginx.virtualHosts.${apiDomain} = {
    enableACME = true;
    forceSSL = true;
    extraConfig = "client_max_body_size 128M;";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8888";
      proxyWebsockets = true;
      # retain/reflect 可能较久。
      extraConfig = "proxy_read_timeout 600s;";
    };
  };

  services.nginx.virtualHosts.${uiDomain} = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9999";
      proxyWebsockets = true;
    };
  };
}
