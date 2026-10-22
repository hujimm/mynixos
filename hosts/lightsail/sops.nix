# lightsail 的系统级 sops：解密 Vaultwarden 管理令牌。
#
# 通用骨架（sops-nix 模块、age key 路径、EasyTier 口令声明）见
# modules/nixos/security/sops-cloud.nix；本机只写自己的 defaultSopsFile 与密钥。
#
# Hindsight / hermes 的密钥已随服务停用移出；原文件归档在
# modules/_trash/lightsail-hermes-hindsight/。
{ config, ... }:

{
  imports = [ ../../modules/nixos/security/sops-cloud.nix ];

  sops = {
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
