{ ... }:
{
  # 密钥管理模块：sops-nix 声明式解密，/run/secrets 下按需放置
  imports = [
    ./sops.nix
    ./easytier-secret.nix
    ./polkit.nix
  ];
}
