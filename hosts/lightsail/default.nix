# AWS Lightsail host（nixosConfigurations.lightsail）。
# ./bootstrap.nix 是机器基础配置，同时用于 nixos-infect 就地安装（故刻意不放
# 依赖秘密/服务的模块）；./sops.nix 与 ./vaultwarden.nix 只在作为 flake host 时加载。
{
  ...
}:

{
  imports = [
    ./bootstrap.nix
    ./sops.nix
    ./vaultwarden.nix
    ./hindsight.nix
  ];
}
