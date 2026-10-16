# AWS Lightsail host（nixosConfigurations.lightsail）。
# ./bootstrap.nix 是机器基础配置，同时用于 nixos-infect 就地安装（故刻意不放
# 依赖秘密/服务的模块）；./sops.nix、./vaultwarden.nix 与 ./hermes.nix 只在作为
# flake host 时加载。
{
  ...
}:

{
  imports = [
    ./bootstrap.nix
    ./sops.nix
    ./vaultwarden.nix
    ./hindsight.nix
    ./hermes.nix
    ../../modules/nixos/network
  ];

  # EasyTier 组网：拓扑与虚拟 IP 见 modules/nixos/network/easytier-nodes.nix
  # （本机 = lightsail，10.144.144.4，作为叶子节点连 aliyun 锚点）。
  my.easytier.enable = true;
}
