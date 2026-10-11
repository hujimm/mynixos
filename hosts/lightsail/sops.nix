# lightsail 的系统级 sops：只解密 Vaultwarden 管理令牌。
#
# 与 aliyun 一致：age 私钥不从文件读取，而是由 SSH host key 派生
# （sops-nix 内部调用 ssh-to-age）。因此本机的 age 公钥已列为
# modules/nixos/security/.sops.yaml 里 secrets/vaultwarden.yaml 的收件人。
#
# 取公钥（在 lightsail 上）：
#   nix shell nixpkgs#ssh-to-age -c ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
{ inputs, config, pkgs, ... }:

{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  environment.systemPackages = [ pkgs.sops ];

  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ../../modules/nixos/security/secrets/vaultwarden.yaml;

    secrets."vaultwarden-admin-token" = { };

    # 渲染成 systemd EnvironmentFile 供 vaultwarden 服务读取。
    # 明文只在激活期从 /run/secrets 产生，不落 world-readable 的 nix store。
    templates."vaultwarden-env" = {
      content = "ADMIN_TOKEN=${config.sops.placeholder."vaultwarden-admin-token"}";
      mode = "0400";
    };
  };
}
