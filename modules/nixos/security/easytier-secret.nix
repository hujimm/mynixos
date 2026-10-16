# EasyTier 网络口令的 sops 声明（桌面 / aliyun / lightsail 共用）。
#
# 口令文件路径与模板内容全网一致，各机只是各自的 age 私钥不同——那部分仍由各 host
# 自己的 sops.nix 负责（本机 keyFile、云主机 SSH host key 派生）。凡是要加入 EasyTier
# 的 host，让其 sops 配置 import 本文件即可，避免三份重复的 secret/template。
{ config, ... }:

{
  sops.secrets."easytier-network-secret".sopsFile = ./secrets/easytier.yaml;

  # 渲染成 systemd EnvironmentFile，供 easytier-core 读取配置时展开 ${ET_NETWORK_SECRET}
  # （见 modules/nixos/network/easytier.nix）。
  sops.templates."easytier-env" = {
    content = "ET_NETWORK_SECRET=${config.sops.placeholder."easytier-network-secret"}";
    mode = "0400";
  };
}
