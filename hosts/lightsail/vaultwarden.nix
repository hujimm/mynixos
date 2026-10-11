# Vaultwarden：自用、Bitwarden 客户端全兼容的密码服务器。
#
# 拓扑：客户端 --https--> nginx(80/443, Let's Encrypt) --http--> 127.0.0.1:8222 vaultwarden
#   - 服务器在 AWS ap-southeast-2（海外），无需 ICP 备案，直接开 80/443；
#   - 证书走 ACME HTTP-01（占 80），故无 DNS API / token 依赖（DNS 在 Cloudflare，
#     部署前需先加 A 记录且【关闭橙云代理】，否则 Let's Encrypt 校验会被 Cloudflare 拦）；
#   - 反代与 WebSocket 路径由 services.vaultwarden.configureNginx 自动生成，
#     这里只在同一 vhost 上补 enableACME 与安全头/上传体积/WS 超时。
{ config, ... }:

let
  domain = "vault.liyinuo.tech";
in
{
  services.vaultwarden = {
    enable = true;
    domain = domain;
    dbBackend = "sqlite"; # 几台设备，SQLite 足够且零依赖
    backupDir = "/var/backup/vaultwarden"; # 模块每日 23:00 在线备份（同盘，异地备份另做）
    configureNginx = true; # 自动建 vhost + /notifications/{hub,anonymous-hub} WebSocket 转发
    environmentFile = config.sops.templates."vaultwarden-env".path; # ADMIN_TOKEN（sops 渲染）

    config = {
      # ⚠️ 首次注册账号时临时改成 true 部署一次，注册完立即改回 false 再部署。
      # 不要通过 /admin 页面切换：那会写进 config.json 并永久覆盖此处设置。
      SIGNUPS_ALLOWED = false;
      # 不显示"密码提示"，减少信息泄露面。
      SHOW_PASSWORD_HINT = false;
      # 可选（暂不启用）：
      #   SMTP_*  —— 邀请成员 / 邮件 2FA / 找回密码
      #   PUSH_*  —— 移动端推送，需向 bitwarden.com/host 申请 id/key 并上报元数据
    };
  };

  # Let's Encrypt：HTTP-01。邮箱用于到期提醒与账号注册。
  security.acme = {
    acceptTerms = true;
    defaults.email = "hulu@liyinuo.tech";
  };

  # 全局 TLS/代理推荐设置；recommendedProxySettings 会注入 X-Real-IP，
  # 让 Vaultwarden 拿到真实客户端 IP 做登录限流。
  services.nginx.recommendedTlsSettings = true;
  services.nginx.recommendedProxySettings = true;

  services.nginx.virtualHosts.${domain} = {
    enableACME = true; # 与模块的 forceSSL 配合，为该域名签发证书
    extraConfig = ''
      # 允许上传大附件（nginx 默认 1m，不改会失败）
      client_max_body_size 128M;

      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header Referrer-Policy "same-origin" always;
      add_header X-Robots-Tag "noindex, nofollow" always;
    '';
    # WebSocket 心跳间隔可能超过默认 60s 的 proxy_read_timeout，单独放宽。
    locations."= /notifications/hub".extraConfig = "proxy_read_timeout 3600s;";
    locations."= /notifications/anonymous-hub".extraConfig = "proxy_read_timeout 3600s;";
  };

  # HTTP-01 需要 80，正常访问走 443（forceSSL 会把 80 跳转到 443）。
  # Lightsail 控制台 Networking 页的防火墙是独立一层，需另行放行 80/443。
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
