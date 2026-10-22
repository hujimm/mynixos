# MATLAB R2020b 启动器（2026-10 弃用）。本体和许可证都不进 Nix：官方安装器装到
# ~/MATLAB/R2020b，许可证在 ~/.matlab/（按 HOSTID 绑定），安装位置由 ~/.config/matlab/nix.sh
# 提供。依赖清单抄自 sceptri/nix-matlab 的 common.nix，其中 buildFHSEnv 改名、
# gnome2.gtk → 按需引入的 gtk2、mesa.drivers → mesa 三处是与上游的差异。
{ pkgs, lib, ... }:
let
  matlabTargetPkgs =
    ps:
    (with ps; [
      cacert
      alsa-lib # libasound2
      atk
      glib
      glibc
      cairo
      cups
      dbus
      fontconfig
      gdk-pixbuf
      # 捆绑的 freetype 2.10 缺 FT_Get_Color_Glyph_Layer，与新版 harfbuzz 冲突。
      freetype
      gst_all_1.gst-plugins-base
      gst_all_1.gstreamer
      gtk3
      nspr
      nss
      pam
      pango
      python3
      libselinux
      libsndfile
      glibcLocales
      procps
      unzip
      zlib

      at-spi2-atk
      at-spi2-core
      libdrm
      mesa

      gcc
      gfortran

      udev
      jre
      ncurses

      # 缺了 Simulink 里键盘输入会失灵。
      libxkbcommon
      xkeyboard_config

      libglvnd

      libuuid
      libxcrypt
      libxcrypt-legacy

      wmname
    ])
    ++ lib.optional (builtins.hasAttr "gtk2" ps) ps.gtk2
    ++ (with ps; [
      libsm
      libx11
      libxcb
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxft
      libxi
      libxinerama
      libxrandr
      libxrender
      libxt
      libxtst
      libxxf86vm
    ]);

  runScriptPrefix =
    { errorOut ? true }:
    ''
      # MATLAB 只认 X11。
      export QT_QPA_PLATFORM=xcb
      if [[ -f ~/.config/matlab/nix.sh ]]; then
        source ~/.config/matlab/nix.sh
    ''
    + lib.optionalString errorOut ''
      else
        echo "nix-matlab-error: 找不到 ~/.config/matlab/nix.sh，请先安装 MATLAB 并写入 INSTALL_DIR" >&2
        exit 1
      fi
      if [[ ! -d "$INSTALL_DIR" ]]; then
        echo "nix-matlab-error: INSTALL_DIR $INSTALL_DIR 不是目录" >&2
        exit 2
    ''
    + ''
      fi
    '';

  matlabDesktop = pkgs.makeDesktopItem {
    desktopName = "MATLAB";
    name = "matlab";
    exec = "@out@/bin/matlab -desktop %F";
    icon = "matlab";
    categories = [
      "Utility"
      "TextEditor"
      "Development"
      "IDE"
    ];
    mimeTypes = [
      "text/x-octave"
      "text/x-matlab"
    ];
    keywords = [
      "science"
      "math"
      "matrix"
      "numerical computation"
      "plotting"
    ];
  };
in
{
  environment.systemPackages = [
    (pkgs.buildFHSEnv {
      name = "matlab";
      targetPkgs = matlabTargetPkgs;
      extraInstallCommands = ''
        install -Dm644 ${matlabDesktop}/share/applications/matlab.desktop $out/share/applications/matlab.desktop
        substituteInPlace $out/share/applications/matlab.desktop \
          --replace "@out@" ${placeholder "out"}
      '';
      runScript = pkgs.writeScript "matlab-runner" (
        (runScriptPrefix { }) + ''
          # 用 Nix 的 libstdc++ 盖掉 R2020b 自带的旧库；无传统 WM 下要给窗口打
          # WM_NAME=LG3D hint，否则界面空白（等窗口出现后再打）。
          ( sleep 6; wmname LG3D >/dev/null 2>&1 ) &
          exec env \
            LD_PRELOAD=/lib/libstdc++.so \
            LD_LIBRARY_PATH=/run/opengl-driver/lib/dri/ \
            $INSTALL_DIR/bin/matlab -softwareopengl "$@"
        ''
      );
      meta.description = "MATLAB R2020b（命令式装到家目录，FHS 启动器）";
    })

    (pkgs.buildFHSEnv {
      name = "matlab-shell";
      targetPkgs = matlabTargetPkgs;
      runScript = pkgs.writeScript "matlab-shell-runner" (
        (runScriptPrefix { errorOut = false; }) + ''
          cat <<'EOF'
          ============================
          matlab-shell（R2020b 安装用）

          1. 学校账号去 mathworks.com/mwaccount 下 Previous releases 的 R2020b Linux 包，unzip -X -K 解压
          2. 在此 shell 里跑 ./install，装到 ~/MATLAB/R2020b，学校账号在线激活
             安装器窗口不出来：先删安装包里的 sys/os/glnxa64/libstdc++.so.6* 和 bin/glnxa64/libstdc++.so.6* 再重跑
          3. 写入 ~/.config/matlab/nix.sh：INSTALL_DIR=$HOME/MATLAB/R2020b
          4. 退出此 shell，跑 matlab -desktop 验证
          ============================
          EOF
          exec bash
        ''
      );
      meta.description = "跑 MATLAB 官方安装器用的 FHS shell";
    })
  ];
}
