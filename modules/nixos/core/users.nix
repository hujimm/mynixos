{
  config,
  ...
}:
{
  users.users.orion = {
    isNormalUser = true;
    description = "Orion";

    # 密码 hash 由 sops 在用户创建前解密(neededForUsers)，见 modules/nixos/security/sops.nix
    hashedPasswordFile = config.sops.secrets."orion-password-hash".path;

    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };

  # 只对重建与清理放行免密，其余 sudo 仍要密码。
  security.sudo.extraRules = [
    {
      users = [ "orion" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nix-collect-garbage";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
