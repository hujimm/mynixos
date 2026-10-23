{ inputs, pkgs, ... }:

{
  imports = [
    inputs.noctalia-greeter.nixosModules.default
  ];

  services.displayManager.noctalia-greeter = {
    enable = true;

    # 完整声明式 greeter.toml，每次激活时经 tmpfiles L+ 覆盖写入
    # /var/lib/noctalia-greeter/greeter.toml（settings 可以是 attrset / TOML 字符串 / 路径）
    settings = {
      # 默认会话：Umbriel。取值是会话 .desktop 条目的 Name=，不是文件名；
      # 匹配大小写不敏感（本机 umbriel.desktop 的 Name 是 "Umbriel"）。
      # 权威列表：noctalia-greeter sessions
      session.default = "umbriel";

      # 默认用户：直接进入密码步骤（Esc 或返回键可回到用户列表）。
      # 必须是 /etc/passwd 中的登录名
      user.default = "orion";

      # 配色方案固定为 Synced（即 Sync Now 同步来的外观）。
      # 未完成首次同步前没有调色板，会回退到内置默认外观
      appearance.scheme = "Synced";

      # 密码遮罩与 shell 一致（random:每次轮换字形,防偷窥）
      appearance.password_style = "random";

      # 隐藏 Noctalia 品牌 logo,登录界面更干净
      appearance.hide_logo = true;

      # 无输入 300 秒后熄灭输出（0 或省略 = 永不熄屏；范围 0-86400）
      idle.timeout = 300;

      # 光标：与桌面一致（modules/hm/desktop/cursor.nix 同主题同尺寸）。
      # 主题包不在默认搜索路径，必须用 path 指到 share/icons
      cursor = {
        theme = "phinger-cursors-dark";
        size = 24;
        path = "${pkgs.phinger-cursors}/share/icons";
      };

      # 登录界面键盘布局（输密码用；与 console.keyMap = "us" 一致）
      keyboard.layout = "us";
    };
  };

  # Greeter 的会话发现路径包含 /run/current-system/sw/share/wayland-sessions
  # （README 明列的 NixOS 会话来源）。默认 pathsToLink 不含它，
  # 补上后 niri.desktop 会被链接进去，保证会话在任何环境下都能被发现
  environment.pathsToLink = [ "/share/wayland-sessions" ];
}
