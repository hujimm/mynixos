# aliyun 的系统级 sops：只解密 EasyTier 网络口令。
#
# 通用骨架（sops-nix 模块、age key 路径、EasyTier 口令声明）见
# modules/nixos/security/sops-cloud.nix。本机只额外指定默认加密文件。
{ ... }:

{
  imports = [ ../../modules/nixos/security/sops-cloud.nix ];

  # 本机只解密这一项，故把它设为默认文件。
  sops.defaultSopsFile = ../../modules/nixos/security/secrets/easytier.yaml;
}
