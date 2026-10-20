# nixd LSP 配置:纯数据文件,不走 module 系统,由 zed-editor.nix 直接 import。
# flakeRoot:传给 nixd 的 getFlake 仓库路径,默认 "./." 表示跟随
# nixd 启动时的工作目录(即编辑器打开的文件夹),想固定用绝对路径
# 时改这里一处即可,例如 { flakeRoot = "/home/orion/mynixos"; }。
{
  flakeRoot ? "./.",
}:
let
  flake = "builtins.getFlake (builtins.toString ${flakeRoot})";
in
{
  nixpkgs = {
    expr = "import (${flake}).inputs.nixpkgs { }";
  };
  formatting = {
    command = [ "nixfmt" ];
  };
  options = {
    nixos = {
      expr = "(${flake}).nixosConfigurations.mynixos.options";
    };
    "home-manager" = {
      expr = "(${flake}).nixosConfigurations.mynixos.options.home-manager.users.type.getSubOptions []";
    };
  };
  diagnostic = {
    suppress = [ "sema-extra-with" ];
  };
}
