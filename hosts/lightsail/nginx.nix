# lightsail 对外基础设施：nginx 反代 + Let's Encrypt（ACME）。
# 全机共用的部分都在这里；各服务（vaultwarden / hindsight / hermes）只声明自己的 vhost。
{ ... }:

{
  services.nginx.enable = true;

  # 全局 TLS/代理推荐设置；recommendedProxySettings 会注入 X-Real-IP，
  # 让后端服务拿到真实客户端 IP（如 Vaultwarden 的登录限流）。
  services.nginx.recommendedTlsSettings = true;
  services.nginx.recommendedProxySettings = true;

  # ACME 走 HTTP-01（校验占 80）；邮箱用于 LE 到期提醒与账号注册。
  # DNS 在 Cloudflare：部署前需先加 A 记录且【关闭橙云代理】，否则校验会被 Cloudflare 拦。
  security.acme = {
    acceptTerms = true;
    defaults.email = "hulu@liyinuo.tech";
  };

  # 80 供 ACME 校验与跳转，443 供访问（forceSSL 会把 80 跳转到 443）。
  # Lightsail 控制台 Networking 页的防火墙是独立一层，需另行放行 80/443。
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
