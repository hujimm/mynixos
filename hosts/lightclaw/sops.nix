# lightclaw 的系统级 sops：只解密 OpenClaw 的密钥。
#
# 本机**不在 EasyTier 网格**，故不 import sops-cloud.nix（那会连带引入 easytier-secret.nix，
# 声明网络口令并要求本机是 easytier.yaml 的接收者）。这里只放 sops-nix 的最小骨架 +
# 本机自己的密钥声明。
#
# age 私钥由本机 SSH host key 派生（sops-nix 内部调用 ssh-to-age）；
# 本机 age 公钥已列在 modules/nixos/security/.sops.yaml。
{ inputs, pkgs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    # EasyTier 口令声明 + easytier-env 模板（本机已加入组网）
    ../../modules/nixos/security/easytier-secret.nix
  ];

  environment.systemPackages = [ pkgs.sops ];

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ../../modules/nixos/security/secrets/openclaw.yaml;

  # OpenClaw 密钥：归 openclaw 用户所有（它的 systemd 用户服务要能读）。
  sops.secrets."openclaw-telegram-bot-token" = {
    owner = "openclaw";
    mode = "0400";
  };
  sops.secrets."openclaw-gateway-token" = {
    owner = "openclaw";
    mode = "0400";
  };
  sops.secrets."openclaw-opencode-go-api-key" = {
    owner = "openclaw";
    mode = "0400";
  };
  sops.secrets."openclaw-exa-api-key" = {
    owner = "openclaw";
    mode = "0400";
  };
  sops.secrets."openclaw-tavily-api-key" = {
    owner = "openclaw";
    mode = "0400";
  };
  sops.secrets."openclaw-github-token" = {
    owner = "openclaw";
    mode = "0400";
  };
}
