# DeepSeek Harness 桌面 Web 端（HM 模块，2026-10 弃用，日常改用 OpenCode）。
# 依赖 flake 输入 github:Moraxyc/deepseek-harness.nix。
{
  inputs,
  pkgs,
  config,
  ...
}:
{
  imports = [ inputs.deepseek-harness.homeModules.default ];

  programs.dsh = {
    enable = true;
    profiles.web = {
      bundles = [
        pkgs.dsh.bundles.web-app
      ];
      mode = "managed";
    };

    defaultProfile = config.programs.dsh.profiles.web.materializedName;
  };

  services.dsh = {
    enable = true;
    profile = config.programs.dsh.profiles.web.materializedName;
    port = 3080;
  };
}
