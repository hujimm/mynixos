# OpenCode v1 的 HM 配置（2026-10 弃用，现用 modules/hm/ai-agent/opencode2.nix）。
{
  pkgs,
  inputs,
  ...
}:
{
  programs.opencode = {
    enable = true;
    extraPackages = with pkgs; [
      uv
      nixd
      nixfmt
    ];

    settings = {
      permission = {
        edit = "ask";
        bash = "allow";
        webfetch = "allow";
        question = "allow";
      };
      autoupdate = false;
      lsp = {
        nixd = {
          command = [ "nixd" ];
          env = {
            NIX_PATH = "nixpkgs=${inputs.nixpkgs}";
          };
          initialization = {
            nixd = import ../../hm/common/nixd.nix { };
          };
        };
      };
      formatter = true;
    };

    tui = {
      theme = "system";
      scroll_acceleration.enabled = true;
      diff_style = "auto";
      mouse = true;
      attention = {
        enabled = true;
        notifications = true;
        sound = true;
        volume = 0.4;
      };
    };
  };
}
