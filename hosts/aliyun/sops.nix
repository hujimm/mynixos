# aliyun 的系统级 sops：只解密 EasyTier 网络口令。
#
# 云主机是独立 host，不复用桌面的 modules/nixos/security 目录（那里含 orion 密码 hash、
# github-token 等只应留在本机的秘密），因此单独导入 sops-nix，并只 import 单用途的
# easytier-secret.nix 片段（仅声明 EasyTier 口令与 easytier-env 模板）。
#
# age 私钥不从文件读取，而是由 SSH host key 派生（sops-nix 内部调用 ssh-to-age）：
# 需先把 /etc/ssh/ssh_host_ed25519_key.pub 转换出的 age 公钥列为
# modules/nixos/security/.sops.yaml 里 secrets/easytier.yaml 的收件人。
#
# 取公钥（在 aliyun 上）：
#   nix shell nixpkgs#ssh-to-age -c ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
{ inputs, pkgs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    # 共享的 EasyTier 口令声明 + easytier-env 模板（阿里云只解密这一项）
    ../../modules/nixos/security/easytier-secret.nix
  ];

  environment.systemPackages = [ pkgs.sops ];

  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ../../modules/nixos/security/secrets/easytier.yaml;
  };
}
