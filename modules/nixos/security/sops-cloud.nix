# 云主机（aliyun / lightsail）共用的 sops 骨架。
# age 私钥不从文件读取，而是由 SSH host key 派生（sops-nix 内部调用 ssh-to-age）；
# 各机的 age 公钥需列在 modules/nixos/security/.sops.yaml 对应文件的规则里。
#
# 各 host 的 sops.nix 只需再写 defaultSopsFile / secrets / templates。
{ inputs, pkgs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    # 共享的 EasyTier 口令声明 + easytier-env 模板
    ./easytier-secret.nix
  ];

  environment.systemPackages = [ pkgs.sops ];

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
}
