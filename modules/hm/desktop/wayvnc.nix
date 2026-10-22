# 手机远程桌面：WayVNC 由 Home Manager 的 services.wayvnc 管理（生成 ~/.config/wayvnc/config
# 和 systemd 用户单元，随 graphical-session.target 起，即 niri-session 登录后自动启动）。
#
# 只绑 EasyTier 虚拟地址，不监听 0.0.0.0：手机（10.144.144.3）经组网直连
# 10.144.144.2:5900，公网和局域网都碰不到。靠私有网络隔离，不额外设 VNC 口令。
# 需要口令时加 settings.enable_auth = true（走 PAM，用本机账号密码，明文不落 store）。
#
# 防火墙只有 NixOS 层能动：modules/nixos/desktop/wayvnc.nix 在 tun0 上放行 5900。
#
# niri 前提：25.05 起实现 wlr-virtual-pointer，wayvnc 的指针可正常操作；但虚拟键盘
# 不能触发 niri 自身的键位绑定，手机输入法组好的中文也不会作为文本送达——
# 中文内容请用剪贴板同步粘贴。
{ ... }:

let
  # 拓扑的唯一事实来源：modules/nixos/network/easytier-nodes.nix
  topo = import ../../nixos/network/easytier-nodes.nix;
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
