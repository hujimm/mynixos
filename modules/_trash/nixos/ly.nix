# ly 显示管理器（2026-09 弃用，现用 noctalia-greeter）。
{ ... }:
{
  services.displayManager.ly = {
    enable = true;
    settings = {
      fg = 7;
      bg = 0;
      # clock = "%c";
      hide_borders = true;
      bigclock = true;
      animate = true;
      animation = "matrix";
    };
  };
}
