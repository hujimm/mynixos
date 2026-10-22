# WayVNC 的防火墙放行。服务端与监听地址在 modules/hm/desktop/wayvnc.nix，
# 只监听 EasyTier 网卡地址，所以这里只对 tun0 放行 5900，不对其他网卡开放。
{ ... }:

{
  networking.firewall.interfaces."tun0".allowedTCPPorts = [ 5900 ];
}
