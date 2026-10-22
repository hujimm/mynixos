# AstrBot + NapCat（2026-09 弃用）。镜像走 m.daocloud.io，镜像站失效时换回
# soulter/astrbot:latest 与 mlikiowa/napcat-docker:latest。
{ ... }:
{
  virtualisation.oci-containers = {
    backend = "podman";

    containers = {
      astrbot = {
        image = "m.daocloud.io/docker.io/soulter/astrbot:latest";
        # 6199 只给容器网络内的 napcat 用，发布到宿主等于任何人可冒充 OneBot 客户端。
        ports = [ "6185:6185" ];
        environment.TZ = "Asia/Shanghai";
        volumes = [
          "/var/lib/astrbot/data:/AstrBot/data"
          "/etc/localtime:/etc/localtime:ro"
        ];
        extraOptions = [ "--security-opt=no-new-privileges" ];
      };

      napcat = {
        image = "m.daocloud.io/docker.io/mlikiowa/napcat-docker:latest";
        dependsOn = [ "astrbot" ];
        environment = {
          # 该模式会生成 onebot11.json，让 NapCat 作为 WS 客户端连 ws://astrbot:6199/ws。
          MODE = "astrbot";
          # 不设 NAPCAT_UID/GID：镜像默认以 root 写文件（与上游 compose 一致）。
        };
        ports = [ "6099:6099" ];
        volumes = [
          "/var/lib/astrbot/data:/AstrBot/data"
          "/var/lib/astrbot/napcat/config:/app/napcat/config"
          "/var/lib/astrbot/ntqq:/app/.config/QQ"
        ];
      };
    };
  };

  # 不开 dns_enabled 时 podman0 上没有 53/UDP，napcat 解析不到 astrbot。
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # 用用户名/组名而不是数字：普通用户的 uid 在激活时才分配。
  systemd.tmpfiles.rules = [
    "d /var/lib/astrbot 0755 orion users -"
    "d /var/lib/astrbot/data 0755 orion users -"
    "d /var/lib/astrbot/napcat 0755 orion users -"
    "d /var/lib/astrbot/napcat/config 0755 orion users -"
    "d /var/lib/astrbot/ntqq 0755 orion users -"
  ];

  networking.firewall.allowedTCPPorts = [ 6185 6099 ];
}
