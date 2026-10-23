# Umbriel 合成器；用户级配置在 modules/hm/desktop/umbriel.nix。
{ inputs, ... }:

{
  imports = [ inputs.umbriel.nixosModules.default ];

  programs.umbriel.enable = true;
}
