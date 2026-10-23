# Sunshine + Moonlight：手机远程控制桌面（取代 wayvnc）。
#
# 服务本体是 systemd 用户单元（graphical-session.target），随 niri 会话登录启动。
# 输入注入走 /dev/uinput（模块自动开 hardware.uinput.enable 并装 udev 规则），
# 不依赖 compositor 的虚拟键盘协议，所以 niri 下键盘、鼠标都正常。
# 若日志报 /dev/uinput 权限被拒（uaccess 没覆盖到当前会话时），把用户加进 input 组。
#
# 抓屏用 wlr-screencopy（niri 支持 v1–v3），不需要 capSysAdmin；KMS 抓屏才要。
# 只绑 EasyTier 虚拟地址并只对 tun0 放行端口；手机 Moonlight 里手动添加
# 10.144.144.2 配对——mDNS 发现不走 tun0，自动搜不到属于正常。
# 首次登录后到 https://10.144.144.2:47990 建账号密码。
#
# settings 一设，Sunshine Web UI 就只能配对、不能改配置；改流参数改这里。
# 若日志里编码器回退到 software，再显式加 encoder = "quicksync"（Intel）或 "vaapi"。
{ ... }:

let
  # 拓扑的唯一事实来源：modules/nixos/network/easytier-nodes.nix
  topo = import ../network/easytier-nodes.nix;
in
{
  services.sunshine = {
    enable = true;
    autoStart = true;

    settings = {
      sunshine_name = "vostro-3420";
      # tun0 还没起来时绑定失败，单元按 Restart=on-failure 重试。
      bind_address = "10.144.144.${toString topo.nodes."vostro-3420"}";
      capture = "wlr";
    };
  };

  # 端口相对基址 port=47989 的偏移，见 services.sunshine 模块：
  # TCP -5/0/1/21，UDP +9/10/11/13/21。
  networking.firewall.interfaces."tun0" = {
    allowedTCPPorts = [ 47984 47989 47990 48010 ];
    allowedUDPPorts = [ 47998 47999 48000 48002 48010 ];
  };
}
