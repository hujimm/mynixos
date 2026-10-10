# AWS Lightsail host（nixosConfigurations.lightsail）。
# 实际配置在 ./bootstrap.nix —— 那份同时用于 nixos-infect 就地安装，
# 这里只把它作为 flake host 复用，保持单一来源。
{
  ...
}:

{
  imports = [ ./bootstrap.nix ];
}
