# EasyTier 网络口令的 sops 声明（桌面 / aliyun / lightsail 共用）。
# 各机的 age 私钥仍由各自 sops.nix 管；凡加入 EasyTier 的 host，让其 sops 配置 import 本文件即可。
{ config, ... }:

{
  sops.secrets."easytier-network-secret".sopsFile = ./secrets/easytier.yaml;

  # 渲染成 systemd EnvironmentFile，供 easytier-core 展开 ${ET_NETWORK_SECRET}
  # （见 modules/nixos/network/easytier.nix）。
  sops.templates."easytier-env" = {
    content = "ET_NETWORK_SECRET=${config.sops.placeholder."easytier-network-secret"}";
    mode = "0400";
  };
}
