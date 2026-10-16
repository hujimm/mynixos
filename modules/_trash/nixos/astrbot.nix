# AstrBot + NapCat：直接用官方 OCI 镜像跑，不塞进 Nix 闭包。
#
# 【已弃用，留作以后重启用时的参考】本文件是桌面版（vostro-3420）配置。
# 同一套配置也曾在阿里云 ECS 上跑过（原 hosts/aliyun/astrbot.nix，已随弃用删除）。
# 两处功能完全等价（组件、端口、镜像、volumes、no-new-privileges、aardvark-dns、
# 防火墙放行逐字一致），只有以下差异，云主机重启时按下表改即可：
#   - 目录属主：桌面用 orion:users（见文末 tmpfiles）；阿里云改用 root:root
#     （云主机没有 orion 用户，容器以 root 运行）。
#   - 端口暴露：桌面只对宿主发布 6185（6199 仅容器网络内给 napcat）；阿里云
#     6185/6099 都对公网开放，务必先改掉 AstrBot 面板默认密码、给 NapCat WebUI
#     设 token。
#   - 登录态：阿里云未迁移 ntqq，首次要用 6099 WebUI 扫码登录 QQ。
#   - 两处镜像都走 m.daocloud.io 镜像站；某天不可用时换回 soulter/astrbot:latest、
#     mlikiowa/napcat-docker:latest。
#
# 为什么用容器而不是打成 Nix 包：AstrBot 依赖极重（Python 3.12 + pandas/faiss/
# python-telegram-bot/wechatpy/markitdown… 另外还要 Node.js、ffmpeg、noto-cjk 字体），
# 而且插件市场会在运行时 pip 装插件、dashboard 缺资源时还会去 GitHub 下载。这些都和
# Nix store 的不可变模型冲突，跑官方镜像最省心。
#
# 组件：
#   * astrbot  soulter/astrbot         WebUI:6185，OneBot v11 WS 服务:6199
#   * napcat   mlikiowa/napcat-docker  MODE=astrbot 会写入 onebot11.json，让 NapCat
#              作为 WS 客户端连 ws://astrbot:6199/ws；自带 WebUI:6099
#
# 网络：两个容器都接 Podman 默认桥网络，靠容器名互相解析（下面开了 dns_enabled）。
#
# 数据：bind 到 /var/lib/astrbot/ 下，方便备份/查看。napcat 与 astrbot 共享 data 目录
#       是照抄上游 NapCat 的 compose，保持与官方一致。
#
# 镜像默认走 DaoCloud 镜像站（国内直连 Docker Hub 太慢/常失败）。若某天镜像站不可用，
# 把 image 换回官方名即可：
#   image = "soulter/astrbot:latest";
#   image = "mlikiowa/napcat-docker:latest";
{ ... }:
{
  virtualisation.oci-containers = {
    # stateVersion ≥ 22.05 时 backend 默认就是 podman，这里显式写出以免以后默认变化
    backend = "podman";

    containers = {
      astrbot = {
        image = "m.daocloud.io/docker.io/soulter/astrbot:latest";
        # 只发布 WebUI 6185 到宿主。OneBot v11 的 6199 走容器网络给 napcat 用，
        # 不暴露到宿主：否则局域网里任何人都能直接连上冒充 OneBot 客户端发消息。
        ports = [ "6185:6185" ];
        environment.TZ = "Asia/Shanghai";
        volumes = [
          "/var/lib/astrbot/data:/AstrBot/data"
          "/etc/localtime:/etc/localtime:ro" # 容器内时间与宿主一致
        ];
        # 与上游 compose 的 security_opt 保持一致
        extraOptions = [ "--security-opt=no-new-privileges" ];
      };

      napcat = {
        image = "m.daocloud.io/docker.io/mlikiowa/napcat-docker:latest";
        dependsOn = [ "astrbot" ]; # OneBot WS 客户端，等 AstrBot 起来再启动
        environment = {
          # 预置模板：自动生成 onebot11.json，连 ws://astrbot:6199/ws
          MODE = "astrbot";
          # 不设 NAPCAT_UID/GID：镜像默认以 root 写文件（与上游 compose 一致）。
          # 注意 NixOS 普通用户 uid 是激活时动态分配的，eval 期取不到数值，别硬编码。
        };
        ports = [ "6099:6099" ]; # NapCat WebUI（扫码登录 QQ 用）
        volumes = [
          "/var/lib/astrbot/data:/AstrBot/data"
          "/var/lib/astrbot/napcat/config:/app/napcat/config"
          "/var/lib/astrbot/ntqq:/app/.config/QQ" # QQ 登录态
        ];
      };
    };
  };

  # 开启 Podman 默认网络上的容器名 DNS（aardvark-dns），napcat 才能解析到 astrbot。
  # 不设此项时默认不开，模块也不会放行 podman0 上的 53/UDP。
  # （oci-containers 见 backend=podman 会自动 enable，这里显式写出更清楚。）
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # 建持久化目录。用用户名/组名（tmpfiles 在运行时解析，能对上动态分配的 uid）；
  # orion 属主方便你直接读，容器以 root 跑也能写。
  systemd.tmpfiles.rules = [
    "d /var/lib/astrbot 0755 orion users -"
    "d /var/lib/astrbot/data 0755 orion users -"
    "d /var/lib/astrbot/napcat 0755 orion users -"
    "d /var/lib/astrbot/napcat/config 0755 orion users -"
    "d /var/lib/astrbot/ntqq 0755 orion users -"
  ];

  # Podman 发布端口时会自行插入转发规则，通常已绕过 NixOS firewall；这里仍显式放行，
  # 一是便于阅读，二是万一以后改用 host 网络也不会漏。
  networking.firewall.allowedTCPPorts = [ 6185 6099 ];
}
