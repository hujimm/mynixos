# WayVNC 手机远程桌面（HM 侧，2026-10 弃用，改用 sunshine/moonlight）。
# 服务随 graphical-session.target（niri-session）启动，只绑 EasyTier 地址。
#
# 再加回本仓库时：
#   - 只加下面这段 HM 配置和 projects/wayvnc/nixos.nix 的 tun0 放行，两边都要；
#   - niri 25.05 起实现 wlr-virtual-pointer，指针可用，但虚拟键盘触发不了 niri 键位绑定，
#     手机输入法组好的中文也不会作为文本送达（VNC 只发 keysym，中文靠剪贴板粘贴）；
#   - 要口令加 settings.enable_auth = true，走 PAM 用本机账号密码，明文不落 store。
{ ... }:

let
  # 拓扑的唯一事实来源：modules/nixos/network/easytier-nodes.nix
  topo = import ../../../nixos/network/easytier-nodes.nix;
in
{
  services.wayvnc = {
    enable = true;
    autoStart = true;

    settings = {
      address = "10.144.144.${toString topo.nodes."vostro-3420"}";
      port = 5900;
    };
  };
}
