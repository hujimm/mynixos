{
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/core
    ../../modules/nixos/programs
    ../../modules/nixos/desktop
    ../../modules/nixos/services
    ../../modules/nixos/security
    ../../modules/nixos/network
  ];

  # EasyTier 组网：拓扑与虚拟 IP 见 modules/nixos/network/easytier-nodes.nix。
  # 本机 networking.hostName 是 mynixos，故显式用网格名 vostro-3420（10.144.144.2）。
  my.easytier = {
    enable = true;
    node = "vostro-3420";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = { inherit inputs; }; # 在 hm 中使用 flake 的 inputs 参数
    # 注册 sops-nix 的 Home Manager 模块（noctalia 密钥等用户级解密用）
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];
    users.orion = import ../../home/orion;
  };

  system.stateVersion = "26.05";
}
