{ ... }:
{
  # 桌面栈系统侧：窗口管理器 + 登录界面（用户侧配置在 modules/hm/desktop）
  imports = [
    ./niri.nix
    ./noctalia-greeter.nix
    ./sunshine.nix
  ];
}
