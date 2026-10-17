# Hindsight：自托管 Agent 记忆服务。LLM / Embedding / Reranker 全部走外部 API
# （slim 镜像不含本地模型），数据库用同机 pgvector 容器。
#
# 配置全部经环境变量注入（HINDSIGHT_API_*，它没有配置文件）：
#   - 非密部分（provider / 模型名 / base_url / 鉴权扩展 / worker id）写死在
#     下面的 environment；
#   - 密钥部分（各家 API key、自设的两个口令、DB 密码）由 sops 渲染成
#     EnvironmentFile，经 environmentFiles 注入，明文不落 store（见 ./sops.nix）。
#
# 对外：nginx + Let's Encrypt 两个子域，容器端口只绑 127.0.0.1：
#   - hindsight-api.<域> -> 127.0.0.1:8888（REST /v1…、MCP /mcp/{bank}/ …）
#   - hindsight.<域>     -> 127.0.0.1:9999（Control Plane Web UI）
# 8888 默认无鉴权，故开启内置 ApiKeyTenantExtension；9999 也设了访问口令。
#
# ⚠️ 部署前你要做的：
#   1. 把两个域名改成你自己的，并在 DNS（Cloudflare，关闭橙云）加 A 记录；
#   2. 用 sops 把 secrets/hindsight.yaml 里的占位值换成真实 key（见 sops.nix）；
#   3. 版本 tag（0.10.3-slim）按需更新。
{ config, ... }:

let
  apiDomain = "hindsight-api.liyinuo.tech";
  uiDomain = "hindsight.liyinuo.tech";
in
{
  virtualisation.oci-containers = {
    backend = "podman";

    containers = {
      # 数据库：官方 pgvector 镜像（PostgreSQL 18 + pgvector），数据落在宿主目录。
      hindsight-db = {
        image = "docker.io/pgvector/pgvector:pg18";
        # postgres 入口脚本会把非选项参数透传给 postgres；按小内存机调参。
        cmd = [
          "-c"
          "shared_buffers=128MB"
          "-c"
          "max_connections=50"
        ];
        environmentFiles = [ config.sops.templates."hindsight-db-env".path ];
        volumes = [ "/var/lib/hindsight/pgdata:/var/lib/postgresql/18/docker" ];
        extraOptions = [
          # 上限而非预留：实测个人规模常驻 ~150–250MB。
          "--memory=512m"
          # 【稳定性】OOM 排序：比应用容器晚死（它一死记忆服务就废了），但早于 hermes。
          # 走 --oom-score-adj 的理由同应用容器。
          "--oom-score-adj=400"
          "--health-cmd=pg_isready -U hindsight -d hindsight_db"
          "--health-interval=15s"
          "--health-timeout=5s"
          "--health-retries=5"
          "--health-start-period=30s"
        ];
      };

      # 应用：slim 镜像（无本地模型，embedding/reranker 必须外部）；
      # standalone 版本同一容器内同时跑 API(8888) 与 Control Plane(9999)。
      hindsight = {
        image = "ghcr.io/vectorize-io/hindsight:0.10.3-slim";
        dependsOn = [ "hindsight-db" ];
        environmentFiles = [ config.sops.templates."hindsight-env".path ];
        environment = {
          TZ = "Asia/Shanghai";

          # ---- 外部模型（全部走 API）----
          # LLM：OpenCode Go（内置 provider；必需的 x-opencode-session 头由
          # Hindsight 自动注入，见 engine/cache_affinity.py 的 apply_opencode_session）。
          HINDSIGHT_API_LLM_PROVIDER = "opencode-go";
          HINDSIGHT_API_LLM_MODEL = "cat-jam-free";
          # 回退成员 1（failover 顺序：[0]=cat-jam-free → [1]=deepseek-v4.1-flash）。
          # 成员变量名 HINDSIGHT_API_LLM_<n>_PROVIDER/_MODEL/_API_KEY（n 从 1 连续）。
          HINDSIGHT_API_LLM_1_PROVIDER = "opencode-go";
          HINDSIGHT_API_LLM_1_MODEL = "deepseek-v4.1-flash";
          HINDSIGHT_API_LLM_STRATEGY = builtins.toJSON { mode = "failover"; };

          # Embedding：Cloudflare Workers AI，走它的 OpenAI 兼容口（/ai/v1）。
          # qwen3-embedding-0.6b 原生 1024 维，维度由启动探测自动确定。
          HINDSIGHT_API_EMBEDDINGS_PROVIDER = "openai";
          HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL = "https://api.cloudflare.com/client/v4/accounts/c6f9a27ce7ae62bb8971fde57e40a28c/ai/v1";
          HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL = "@cf/qwen/qwen3-embedding-0.6b";
          # CF 侧输入上限 4096 token；Hindsight 按其分词器计数（可能偏大），遇 400 再减半。
          HINDSIGHT_API_EMBEDDINGS_MAX_INPUT_TOKENS = "4096";

          # Qwen3-Embedding 是 instruction-aware 的；官方检索用法是查询侧带
          # "Instruct: <任务>\nQuery: "、文档侧裸文本（hindsight 分 encode_query /
          # encode_documents，前缀各管一边，文档向量不受影响，故无需重灌索引）。
          # 实测 20 文档 / 20 相关 + 5 无关问句：hit@1 70%→90%、MRR 0.850→0.942、
          # 无关问句最高分 0.340→0.223。任务描述用 CF 自己给的默认那句英文最好；
          # 换成中文描述反而把正负样本分差压小了（+0.107 vs +0.128）。
          # ⚠️ 结尾的 "Query: " 后的空格不能省，改了前缀等于换了查询空间，需重跑门槛校准。
          HINDSIGHT_API_EMBEDDINGS_QUERY_PREFIX = "Instruct: Given a web search query, retrieve relevant passages that answer the query\nQuery: ";

          # Reranker：NVIDIA NIM。Hindsight 的 reranker provider 是固定清单、无任意
          # 透传，NVIDIA 不在其中，故经 LiteLLM SDK 桥接（litellm 是 slim 镜像的
          # 核心依赖，LiteLLM 原生支持 nvidia_nim rerank）。
          # ⚠️ 不要设 HINDSIGHT_API_RERANKER_LITELLM_SDK_API_BASE：一旦路径含
          #    /retrieval/，LiteLLM 会原样使用，从而漏掉 /nvidia/<model>/reranking。
          #    留空即让它拼默认 https://ai.api.nvidia.com/v1/retrieval/<model>/reranking。
          # 纯文本场景可把模型换成 nvidia/llama-nemotron-rerank-1b-v2（vl 版是多模态）。
          # 若此路不通，回退一行：HINDSIGHT_API_RERANKER_PROVIDER = "rrf"。
          HINDSIGHT_API_RERANKER_PROVIDER = "litellm-sdk";
          HINDSIGHT_API_RERANKER_LITELLM_SDK_MODEL = "nvidia_nim/nvidia/llama-nemotron-rerank-vl-1b-v2";

          # 鉴权：8888 默认无鉴权，务必开启（密钥走 EnvironmentFile）。
          HINDSIGHT_API_TENANT_EXTENSION = "hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension";

          # 运维：固定 worker id，避免容器重启后旧任务变孤儿。
          HINDSIGHT_API_WORKER_ID = "hindsight-lightsail";
          HINDSIGHT_API_HOST = "0.0.0.0";
          HINDSIGHT_API_LOG_LEVEL = "info";
          # 后台操作记录保留 30 天（默认 0=永久），防数据库长期膨胀。
          HINDSIGHT_API_OPERATION_RETENTION_DAYS = "30";

          # Control Plane 指向同容器内的 API；其 Bearer token 走 EnvironmentFile。
          HINDSIGHT_CP_DATAPLANE_API_URL = "http://localhost:8888";

          # 近义结论的合并门槛（默认 0.97，越接近 1 越保守）：同一 tag scope 内
          # 两条结论的向量相似度到这个值，才会拿去判断「合并还是各自保留」。
          # 0.97 太严：中文原句与英文摘要这类重复根本进不了比较，因此降到 0.9。
          HINDSIGHT_API_CONSOLIDATION_DEDUP_THRESHOLD = "0.9";
        };
        # 只绑回环；对外由 nginx 终结 TLS。
        ports = [
          "127.0.0.1:8888:8888"
          "127.0.0.1:9999:9999"
        ];
        extraOptions = [
          # 上限而非预留：实测 API+CP 常驻 ~500–750MB。
          "--memory=1024m"
          # 【稳定性】OOM 排序：内存见底时它最先死（分最高），可自动重启、可降级。
          # 必须走 podman 的 --oom-score-adj 而不是 unit 的 OOMScoreAdjust——
          # 容器进程跑在独立的 machine.slice/libpod-*.scope 里，不在 podman-<name>.service
          # 的 cgroup 下，unit 上设的分传不到它。
          "--oom-score-adj=600"
          # 优雅停机：给 API/CP 及 DB 连接收尾的时间（官方脚本建议 ≥30s）。
          "--stop-timeout=30"
          "--security-opt=no-new-privileges"
          # 镜像自带 python3 + hindsight_api.http_probe（官方 start-all.sh 同款）。
          "--health-cmd=python3 -m hindsight_api.http_probe http://localhost:8888/health 5"
          "--health-interval=30s"
          "--health-timeout=10s"
          "--health-retries=5"
          "--health-start-period=180s"
        ];
      };
    };
  };

  # 容器名互解：hindsight -> hindsight-db。
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # 数据目录。PGDATA 需归镜像内的 postgres（uid/gid 999）所有，故预置属主。
  systemd.tmpfiles.rules = [
    "d /var/lib/hindsight 0755 root root -"
    "d /var/lib/hindsight/pgdata 0700 999 999 -"
  ];

  # ---- nginx + Let's Encrypt ----
  # 全机 nginx / ACME / 80-443 见 ./nginx.nix；下面只声明本服务的 vhost。

  services.nginx.virtualHosts.${apiDomain} = {
    enableACME = true;
    forceSSL = true;
    extraConfig = "client_max_body_size 128M;"; # 记忆可带附件上传
    locations."/" = {
      proxyPass = "http://127.0.0.1:8888";
      proxyWebsockets = true;
      extraConfig = "proxy_read_timeout 600s;"; # retain/reflect 可能较久
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
