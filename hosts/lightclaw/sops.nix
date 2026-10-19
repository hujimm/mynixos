# lightclaw 的系统级 sops：最小骨架 + EasyTier 口令（本机已加入组网）。
#
# 本机**不在 sops-cloud.nix 那条线上**（那是 aliyun/lightsail 云主机共用的骨架），
# 但已加入 EasyTier 网格，所以 import easytier-secret.nix（声明网络口令 +
# easytier-env 模板）。
#
# age 私钥由本机 SSH host key 派生（sops-nix 内部调用 ssh-to-age）；
# 本机 age 公钥已列在 modules/nixos/security/.sops.yaml。
#
# 原先这里还声明了一整套 openclaw-* 密钥（telegram / gateway / opencode-go / exa /
# tavily / github / cloudflare + CF Origin 证书）。OpenClaw 已于 2026-10-19 弃用，
# 声明一并摘除；加密文件 secrets/openclaw.yaml 与 .sops.yaml 里对应的规则**暂时保留**
# （没删），要恢复见 modules/_trash/nixos/lightclaw-openclaw.nix 的恢复步骤。
{ inputs, pkgs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    # EasyTier 口令声明 + easytier-env 模板（本机已加入组网）
    ../../modules/nixos/security/easytier-secret.nix
  ];

  environment.systemPackages = [ pkgs.sops ];

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # 默认 sopsFile：本机现在唯一在用的密钥文件（easytier-secret.nix 内部也显式指定了它）。
  sops.defaultSopsFile = ../../modules/nixos/security/secrets/easytier.yaml;
}
