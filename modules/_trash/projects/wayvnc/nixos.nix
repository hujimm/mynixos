# WayVNC 的防火墙放行（NixOS 侧，2026-10 弃用，改用 sunshine/moonlight）。
# 服务端只监听 tun0 上的地址，所以只对 tun0 放行 5900。
{ ... }:

{
  networking.firewall.interfaces."tun0".allowedTCPPorts = [ 5900 ];
}
