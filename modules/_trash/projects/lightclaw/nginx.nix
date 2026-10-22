# nginx 反代 claw.liyinuo.tech → 127.0.0.1:18789 的 WSS（2026-10 弃用）。
#
# 证书用 Cloudflare Origin CA 而不是 ACME：只被 CF 信任，所以必须走橙云、源站只开 443；
# Origin CA 没有 OCSP 响应者，stapling 要关掉，否则刷日志。
{ ... }:

{
  services.nginx.enable = true;
  services.nginx.recommendedTlsSettings = true;
  services.nginx.recommendedProxySettings = true;

  services.nginx.virtualHosts."claw.liyinuo.tech" = {
    onlySSL = true;
    extraConfig = "ssl_stapling off;";

    locations."/" = {
      proxyPass = "http://127.0.0.1:18789";
      proxyWebsockets = true;
      # 会话可能长时间空闲。
      extraConfig = "proxy_read_timeout 3600s;";
    };
  };

  # 只开 443 供 Cloudflare 回源；Lightsail 控制台 Networking 那层需另外放行。
  networking.firewall.allowedTCPPorts = [ 443 ];
}
