# Umbriel 的用户配置：由 modules/hm/desktop/niri-config/ 下的 niri 配置逐项翻译而来。
# 两套配置并存、互不干扰，greeter 默认会话仍是 niri，登录时手动选 Umbriel 试用。
#
# 生成路径：$XDG_CONFIG_HOME/umbriel/config.toml（UMBRIEL 的 HM 模块来自
# flake 输入 inputs.umbriel.homeModules.default）。系统侧（装包、会话注册、portal）
# 在 modules/nixos/desktop/umbriel.nix。
#
# 移植差异（Umbriel 没有对应能力，只能近似或舍弃）：
#   - focus-follows-mouse 没有 max-scroll-amount；cursor.follows_focus 只跟随键盘焦点，
#     不区分“跟随是否会导致视图滚动”
#   - 没有 expel-window-from-column 的独立动作：Mod+Comma/Period 改成并入左/右列，
#     “拆出/并入”的切换语义移到 Mod+BracketLeft/Right
#   - 没有 switch-preset-window-height 的“恢复原高度”，用 secondary-extent:1.0 近似
#   - 没有内置 screenshot-window 动作（Alt+Print），截图走 Noctalia 的 region/fullscreen
#   - niri 的 hotkey-overlay-title/allow-inhibiting/重复控制按 keybinds 的
#     repeat / allow_when_inhibited / allow_when_locked 逐条对应
#   - niri 的 tab-indicator、focus-ring、阴影 spread 没有逐项对应项，取 Umbriel 的最接近键
{ ... }:

{
  programs.umbriel = {
    enable = true;

    settings = {
      general = {
        mod_key = "Super";
        # niri 的 hotkey-overlay { skip-at-startup }
        show_cheatsheet = false;
        # XWayland 按需启动：等它就绪后灌入 ~/.Xresources（Xft.dpi=144），
        # 否则微信/WPS 里 fcitx5 候选框偏小。与 niri 的 spawn-sh-at-startup 等价。
        autostart = [
          "sh -c 'until xrdb -merge ~/.Xresources 2>/dev/null; do sleep 1; done'"
        ];
      };

      # 内屏：niri 的 output "eDP-1"（1920x1080@60 + scale 1.5 + position 0,0）
      output."eDP-1" = {
        mode = "1920x1080@60";
        scale = 1.5;
        position = [ 0 0 ];
      };

      # 合盖时从桌面移除内屏，开盖恢复（Umbriel 不像 niri 那样自动处理）
      events = {
        lid_close = "umbriel msg output-disable:eDP-1";
        lid_open = "umbriel msg output-enable:eDP-1";
      };

      input = {
        keyboard = {
          layout = "us";
        };
        touchpad = {
          tap = true;
          # niri 的 dwt
          disable_while_typing = true;
          natural_scroll = true;
        };
        # niri: focus-follows-mouse max-scroll-amount="0%"
        focus.follows_mouse = true;
        cursor = {
          theme = "phinger-cursors-dark";
          size = 24;
          # niri: warp-mouse-to-focus mode="center-xy"
          follows_focus = true;
        };
      };

      appearance = {
        # window-rule: geometry-corner-radius 8 + clip-to-geometry true
        corner_radius = 8;
        # focus-ring width 2
        border_width = 2;
        # niri: prefer-no-csd
        prefer_no_csd = true;
        shadow = {
          enabled = true;
          softness = 30;
          # niri 还有 spread 5，Umbriel 无对应项
          offset_x = 0;
          offset_y = 5;
        };
        # niri: blur { off } —— 全局关闭（含应用自己请求的模糊）
        blur.enabled = false;
        # niri: tab-indicator { hide-when-single-tab }
        tab_bar.hide_when_single = true;
      };

      layout = {
        # niri 用的就是滚动布局
        mode = "scrolling";
        gap = 2.5;
        # niri preset-column-widths / preset-window-heights（含 1.0 档）
        extent_presets = [ 0.33333 0.5 0.66667 1.0 ];
        scrolling = {
          # niri: default-column-width { proportion 0.5; }
          default_extent_fraction = 0.5;
          # niri: center-focused-column "on-overflow"
          center_focused = "on_overflow";
          # niri: always-center-single-column（Umbriel 没有单列专用开关，用这条近似）
          center_underfull_strip = true;
        };
        tabs = {
          # niri: default-column-display "tabbed"
          default_display = "tabbed";
        };
      };

      # niri animations 段
      animation = {
        enabled = true;
        duration_ms = 150;
        curve = "easeout";
        windows_in = {
          duration_ms = 150;
          # niri: curve "ease-out-expo"
          curve = "0.16,1,0.3,1";
        };
        windows_out = {
          duration_ms = 150;
          # niri: curve "ease-out-quad"
          curve = "easeout";
        };
        windows_move.curve = "spring:1,800";
        windows_resize.curve = "spring:1,800";
        workspaces.curve = "spring:1,1000";
        overview = {
          curve = "spring:1,800";
          workspace_curve = "spring:1,800";
        };
      };

      # niri binds.kdl 逐条翻译。
      # 注意：定义 keybinds 会替换 Umbriel 内置绑定，这里已把要用的全部列出。
      keybinds = {
        # ---------- 应用 ----------
        "Mod+T" = { action = "spawn:kitty -e fish", repeat = false; };
        "Super+E" = { action = "spawn:nautilus", repeat = false; };

        # ---------- Noctalia ----------
        "Mod+Shift+V" = { action = "spawn:noctalia msg panel-open clipboard", repeat = false; };
        "Mod+P" = { action = "spawn:noctalia msg panel-open session", repeat = false; };
        "Mod+W" = { action = "spawn:noctalia msg panel-open wallpaper", repeat = false; };
        "Mod+L" = { action = "spawn:noctalia msg session lock", repeat = false; };
        "Mod+I" = { action = "spawn:noctalia msg settings-open", repeat = false; };
        "Mod+Alt+Space" = { action = "spawn:noctalia msg panel-toggle launcher", repeat = false; };

        # ---------- 窗口与焦点 ----------
        "Mod+O" = { action = "overview-toggle", repeat = false; };
        "Mod+Q" = { action = "window-close", repeat = false; };

        "Mod+Left" = "window-focus-left";
        "Mod+Down" = "window-focus-down";
        "Mod+Up" = "window-focus-up";
        "Mod+Right" = "window-focus-right";

        "Mod+Ctrl+Left" = "column-move-left";
        "Mod+Ctrl+Down" = "window-move-down";
        "Mod+Ctrl+Up" = "window-move-up";
        "Mod+Ctrl+Right" = "column-move-right";

        # ---------- 工作区 ----------
        "Mod+Page_Down" = "workspace-next";
        "Mod+Page_Up" = "workspace-previous";
        "Mod+Ctrl+Page_Down" = "column-move-to-workspace-next";
        "Mod+Ctrl+Page_Up" = "column-move-to-workspace-previous";
        "Mod+Shift+Page_Down" = "workspace-move-down";
        "Mod+Shift+Page_Up" = "workspace-move-up";

        # niri 里 Mod+1..8 对应工作区 2..9（刻意跳过第 1 个工作区）
        "Mod+1" = "workspace-switch:2";
        "Mod+2" = "workspace-switch:3";
        "Mod+3" = "workspace-switch:4";
        "Mod+4" = "workspace-switch:5";
        "Mod+5" = "workspace-switch:6";
        "Mod+6" = "workspace-switch:7";
        "Mod+7" = "workspace-switch:8";
        "Mod+8" = "workspace-switch:9";

        "Mod+Tab" = "workspace-focus-last";

        # ---------- 列与窗口布局 ----------
        "Mod+BracketLeft" = "window-consume-or-expel-left";
        "Mod+BracketRight" = "window-consume-or-expel-right";
        # niri 是 consume-window-into-column / expel-window-from-column，Umbriel 无独立 expel
        "Mod+Comma" = "window-consume-left";
        "Mod+Period" = "window-consume-right";

        "Mod+R" = "window-cycle-primary-extent";
        "Mod+Shift+R" = "window-cycle-secondary-extent";
        "Mod+Ctrl+R" = "window-set-secondary-extent:1.0";
        "Mod+F" = "window-toggle-maximize";
        "Mod+Shift+F" = "window-toggle-fullscreen";
        "Mod+Ctrl+F" = "window-set-primary-extent:1.0";

        "Mod+Minus" = "window-modify-primary-extent:-0.1";
        "Mod+Equal" = "window-modify-primary-extent:0.1";
        "Mod+Shift+Minus" = "window-modify-secondary-extent:-0.1";
        "Mod+Shift+Equal" = "window-modify-secondary-extent:0.1";

        # niri: allow-inhibiting=false —— 被 inhibite 时这个键仍要能按
        "Mod+Escape" = {
          action = "shortcuts-inhibit-toggle";
          allow_when_inhibited = true;
          repeat = false;
        };

        # ---------- 截图 ----------
        "Print" = { action = "spawn:noctalia msg screenshot-region", repeat = false; };
        "Ctrl+Print" = { action = "spawn:noctalia msg screenshot-fullscreen", repeat = false; };
        # niri 的 Alt+Print = screenshot-window（niri 内置动作），Umbriel 无对应，故不绑定

        # ---------- 音量与亮度（锁屏时仍可用） ----------
        "XF86AudioRaiseVolume" = { action = "spawn:noctalia msg volume-up", allow_when_locked = true; };
        "XF86AudioLowerVolume" = { action = "spawn:noctalia msg volume-down", allow_when_locked = true; };
        "XF86AudioMute" = { action = "spawn:noctalia msg volume-mute", allow_when_locked = true; };
        "XF86MonBrightnessUp" = { action = "spawn:noctalia msg brightness-up", allow_when_locked = true; };
        "XF86MonBrightnessDown" = { action = "spawn:noctalia msg brightness-down", allow_when_locked = true; };

        # ---------- 退出 ----------
        # niri 的 quit 无确认框，Umbriel 默认会弹确认
        "Mod+Shift+E" = { action = "session-quit:skip-confirmation", repeat = false; };
      };
    };
  };
}
