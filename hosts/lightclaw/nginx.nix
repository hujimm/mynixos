# lightclaw 对外入口：nginx 反代，给 OpenClaw 网关提供 WSS。
#
# 证书**不用 ACME**：用的是 Cloudflare **Origin CA** 证书（只被 Cloudflare 信任，有效期 15 年），
# 因此访问必须经 Cloudflare（橙云），源站只开 443、不开 80。
# 证书/私钥由 sops 渲染（声明见 ./sops.nix）。
{ config, ... }:

{
  services.nginx.enable = true;
  services.nginx.recommendedTlsSettings = true;
  services.nginx.recommendedProxySettings = true;

  services.nginx.virtualHosts."claw.liyinuo.tech" = {
    onlySSL = true; # 只监听 443（不建 80、不做 80→443 跳转）
    sslCertificate = config.sops.secrets."openclaw-origin-cert".path;
    sslCertificateKey = config.sops.secrets."openclaw-origin-key".path;
    # CF Origin CA 没有 OCSP 响应者，关掉 stapling 免得刷日志。
    extraConfig = "ssl_stapling off;";

    locations."/" = {
      proxyPass = "http://127.0.0.1:18789"; # 网关仍只绑回环
      proxyWebsockets = true; # 网关是 WebSocket
      extraConfig = "proxy_read_timeout 3600s;"; # 长连接（会话可能长时间空闲）
    };
  };

  # 只开 443（供 Cloudflare 回源）。Lightsail 控制台 Networking 那层需另行放行 443。
  networking.firewall.allowedTCPPorts = [ 443 ];
}
