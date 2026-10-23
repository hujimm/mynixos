# Umbriel 合成器（2026-10 试用）：装包、注册登录会话、配 xdg-desktop-portal-umbriel。
#
# 用户级配置（键位、输出、外观等）在 modules/hm/desktop/umbriel.nix，
# 由 flake 输入 inputs.umbriel 的 HM 模块生成 config.toml。
#
# 不把 greeter 的默认会话从 niri 改过来：登录界面里手动选 "Umbriel" 进入试用；
# Umbriel 起不来时还能回 niri（session.default 仍是 niri）。
#
# 模块自身行为：装包、services.displayManager.sessionPackages 注册会话、
# 开 hardware.graphics、把效果预设链到 /run/current-system/sw/share/umbriel/effects，
# 并只写 xdg.portal.config.umbriel.*，不动现有的 config.niri。
{ inputs, ... }:

{
  imports = [ inputs.umbriel.nixosModules.default ];

  programs.umbriel.enable = true;
}
