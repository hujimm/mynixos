# Umbriel 的用户配置；系统侧（装包、会话注册、portal）见 modules/nixos/desktop/umbriel.nix。
{ inputs, ... }:

{
  imports = [ inputs.umbriel.homeModules.default ];

  programs.umbriel = {
    enable = true;

    settings = {
      # Noctalia 跟随壁纸生成；optional 让文件缺失时不报错、生成后自动加载。
      include.optional.files = [ "~/.config/umbriel/noctalia.toml" ];

      general = {
        mod_key = "Super";
        show_cheatsheet = false;
        # Xwayland 惰性启动，等它就绪再灌 Xft.dpi=144；否则微信/WPS 的 fcitx 候选框偏小。
        autostart = [
          "sh -c 'until xrdb -merge ~/.Xresources 2>/dev/null; do sleep 1; done'"
        ];
      };

      output."eDP-1" = {
        mode = "1920x1080@60";
        scale = 1.5;
        position = [
          0
          0
        ];
      };

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
          disable_while_typing = true;
          natural_scroll = true;
        };
        focus.follows_mouse = true;
        cursor = {
          theme = "phinger-cursors-dark";
          size = 24;
          follows_focus = true;
        };
      };

      appearance = {
        corner_radius = 8;
        border_width = 2;
        prefer_no_csd = true;
        shadow = {
          enabled = true;
          softness = 30;
          offset_x = 0;
          offset_y = 5;
        };
        blur.enabled = false;
        tab_bar = {
          style = "indicator";
          position = "left";
          height = 4;
          gap = 5;
          corner_radius = 0;
          hide_when_single = true;
        };
      };

      layout = {
        mode = "scrolling";
        # gap 只接受整数。
        gap = 2;
        extent_presets = [
          0.33333
          0.5
          0.66667
          1.0
        ];
        scrolling = {
          default_extent_fraction = 0.5;
          center_focused = "on_overflow";
          center_underfull_strip = true;
        };
        tabs = {
          default_display = "tabbed";
        };
      };

      overview = {
        zoom = 0.4;
      };

      # 全屏窗口聚焦时热角不生效。
      hot_corners.top_left = {
        enabled = true;
        delay_ms = 100;
        action = "overview-toggle";
      };

      animation = {
        enabled = true;
        duration_ms = 150;
        curve = "easeout";
        windows_in = {
          duration_ms = 150;
          curve = "0.16,1,0.3,1";
        };
        windows_out = {
          duration_ms = 150;
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

      # 定义 keybinds 会替换 Umbriel 内置绑定，要用的必须全部列出。
      keybinds = {
        "Mod+T" = {
          action = "spawn:kitty -e fish";
          repeat = false;
        };
        "Super+E" = {
          action = "spawn:nautilus";
          repeat = false;
        };
        "Mod+Z" = {
          action = "spawn:zen-beta";
          repeat = false;
        };
        "Mod+G" = {
          action = "spawn:google-chrome";
          repeat = false;
        };
        "Mod+V" = {
          action = "spawn:zeditor";
          repeat = false;
        };

        "Mod+Shift+V" = {
          action = "spawn:noctalia msg panel-open clipboard";
          repeat = false;
        };
        "Mod+P" = {
          action = "spawn:noctalia msg panel-open session";
          repeat = false;
        };
        "Mod+W" = {
          action = "spawn:noctalia msg panel-open wallpaper";
          repeat = false;
        };
        "Mod+L" = {
          action = "spawn:noctalia msg session lock";
          repeat = false;
        };
        "Mod+I" = {
          action = "spawn:noctalia msg settings-open";
          repeat = false;
        };
        "Mod+Alt+Space" = {
          action = "spawn:noctalia msg panel-toggle launcher";
          repeat = false;
        };

        "Mod+O" = {
          action = "overview-toggle";
          repeat = false;
        };
        "Mod+Q" = {
          action = "window-close";
          repeat = false;
        };

        "Mod+Left" = "window-focus-left";
        "Mod+Down" = "window-focus-down";
        "Mod+Up" = "window-focus-up";
        "Mod+Right" = "window-focus-right";

        "Mod+Ctrl+Left" = "column-move-left";
        "Mod+Ctrl+Down" = "window-move-down";
        "Mod+Ctrl+Up" = "window-move-up";
        "Mod+Ctrl+Right" = "column-move-right";

        "Mod+Page_Down" = "workspace-next";
        "Mod+Page_Up" = "workspace-previous";
        "Mod+Ctrl+Page_Down" = "column-move-to-workspace-next";
        "Mod+Ctrl+Page_Up" = "column-move-to-workspace-previous";
        "Mod+Shift+Page_Down" = "workspace-move-down";
        "Mod+Shift+Page_Up" = "workspace-move-up";

        # 工作区 1 故意不绑快捷键。
        "Mod+1" = "workspace-switch:2";
        "Mod+2" = "workspace-switch:3";
        "Mod+3" = "workspace-switch:4";
        "Mod+4" = "workspace-switch:5";
        "Mod+5" = "workspace-switch:6";
        "Mod+6" = "workspace-switch:7";
        "Mod+7" = "workspace-switch:8";
        "Mod+8" = "workspace-switch:9";

        "Mod+Tab" = "workspace-focus-last";

        "Mod+BracketLeft" = "window-consume-or-expel-left";
        "Mod+BracketRight" = "window-consume-or-expel-right";
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

        "Mod+Escape" = {
          action = "shortcuts-inhibit-toggle";
          allow_when_inhibited = true;
          repeat = false;
        };

        "Print" = {
          action = "spawn:noctalia msg screenshot-region";
          repeat = false;
        };
        "Ctrl+Print" = {
          action = "spawn:noctalia msg screenshot-fullscreen";
          repeat = false;
        };

        "XF86AudioRaiseVolume" = {
          action = "spawn:noctalia msg volume-up";
          allow_when_locked = true;
        };
        "XF86AudioLowerVolume" = {
          action = "spawn:noctalia msg volume-down";
          allow_when_locked = true;
        };
        "XF86AudioMute" = {
          action = "spawn:noctalia msg volume-mute";
          allow_when_locked = true;
        };
        "XF86MonBrightnessUp" = {
          action = "spawn:noctalia msg brightness-up";
          allow_when_locked = true;
        };
        "XF86MonBrightnessDown" = {
          action = "spawn:noctalia msg brightness-down";
          allow_when_locked = true;
        };

        "Mod+Shift+E" = {
          action = "session-quit:skip-confirmation";
          repeat = false;
        };
      };
    };
  };
}
