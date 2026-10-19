{
  pkgs,
  ...
}:
{
  # nix-ld：在 /lib64 等标准位置提供动态链接器，让未打包的动态链接二进制
  # （如机场提供的 FlashFoxLite GUI、官网下载的 .tar.gz/AppImage 等）能直接在
  # NixOS 上运行。
  #
  # 机制（按 nix-ld 2.0.6 实测）：
  #   * enable = true 会让本模块设置 environment.ldso = "${pkgs.nix-ld}/libexec/nix-ld"，
  #     由 modules/config/ldso.nix 落成 tmpfiles 规则
  #     `L+ /lib64/ld-linux-x86-64.so.2 -> nix-ld/libexec/nix-ld`，
  #     即把 NixOS 自带的 stub-ld 换掉——那句
  #     “NixOS cannot run dynamically linked executables intended for generic
  #     linux environments out of the box” 正是 stub-ld 打印的。
  #     stub-ld 那边只是 mkDefault，本模块的普通赋值优先级更高，不会冲突。
  #   * nix-ld 2.x 为 NIX_LD 与 NIX_LD_LIBRARY_PATH 编入了默认值
  #     （/run/current-system/sw/share/nix-ld/lib/ld.so 与 .../lib），两者缺省时
  #     自动回落。所以 systemd 服务（如 hermes-gateway）不吃这两个变量也能用，
  #     不用往 unit 里补——这点很关键：本模块设置的 environment.sessionVariables
  #     只进登录 shell 的 /etc/set-environment，systemd 用户服务并不读它。
  #   * libraries 是 listOf，按定义拼接：这里写的内容是 **追加** 到模块内置默认集
  #     （zlib、zstd、stdenv.cc.cc、curl、openssl、attr、libssh、bzip2、libxml2、
  #     acl、libsodium、util-linux、xz、systemd）之上的，不用重复上面那批。
  #     libc/libgcc_s/libstdc++ 都不用单写：libc 由加载器按自身目录解析，
  #     libgcc_s 与 libstdc++ 来自默认集里的 stdenv.cc.cc。
  #   * 实际上只需覆盖“未打包二进制直接 NEEDED 的库”：nixpkgs 的库自身都带
  #     RUNPATH，二级依赖由各自的 RUNPATH 解析。多写不报错，只是冗余。
  #   * nix-ld 只接管动态链接器与库查找路径；程序若还硬编码 /usr/lib、/opt 之类
  #     的目录结构，仍要 buildFHSEnv 之类的包装。
  #
  # rebuild 后验证：
  #   readlink -f /lib64/ld-linux-x86-64.so.2    # 应指向 .../nix-ld/libexec/nix-ld
  #   ls /run/current-system/sw/share/nix-ld/lib/  # 这个目录应出现
  #   /home/orion/.hermes/bin/tirith --version    # 应输出 tirith 0.4.1
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # ---- X11 / Wayland 客户端常用 ----
      # 顶层小写新名（旧的 xorg.* 包集已废弃）；xcb-util 系列现名 libxcb-*
      libx11
      libxext
      libxrender
      libxfixes
      libxcomposite
      libxdamage
      libxrandr
      libxtst
      libxi
      libxcursor
      libxinerama
      libxscrnsaver
      libxshmfence
      libxxf86vm
      libsm
      libice
      libxt
      libxmu
      libxft
      libxkbcommon
      libxcb
      libxcb-cursor
      libxcb-util
      libxcb-wm
      libxcb-image
      libxcb-keysyms
      libxcb-render-util

      # ---- OpenGL / Vulkan / 图形驱动 ----
      libGL
      libGLU
      libva
      libgbm
      libdrm
      vulkan-loader
      freeglut
      glew

      # ---- 音频 / 多媒体后端 ----
      pipewire
      alsa-lib
      libpulseaudio
      flac
      libogg
      libvorbis
      libtheora
      libvpx
      speex
      libsamplerate
      libmikmod
      libcanberra

      # ---- GLib / GTK / GNOME ----
      glib
      gtk2
      gtk3
      gdk-pixbuf
      pango
      cairo
      atk
      gsettings-desktop-schemas
      libnotify
      harfbuzz
      freetype
      fontconfig
      expat
      librsvg

      # ---- 图像 / 编解码 ----
      ffmpeg
      libjpeg
      libpng
      libpng12
      libtiff
      pixman

      # ---- SDL（游戏/模拟器常见）----
      SDL
      SDL2
      SDL_image
      SDL_ttf
      SDL_mixer
      SDL2_image
      SDL2_ttf
      SDL2_mixer

      # ---- 系统 / 网络 / 其他常用 ----
      networkmanager
      cups
      dbus
      dbus-glib
      libusb1
      libudev0-shim
      libcap
      libelf
      libgcrypt
      libxcrypt
      libxcrypt-legacy
      libidn
      icu
      nspr
      nss
      krb5
      sane-backends
      pkcs11helper
      gmp
      libgpg-error
      fribidi
      e2fsprogs
      fuse
      coreutils
      pciutils
      zenity

      # ---- Flutter/GTK 类 GUI 的补充（FlashFoxLite GUI 走这条线）----
      libsecret # 密钥环，FlashFoxLite 3.2.1 的适配点之一
      glib-networking # GTK 应用的 TLS / 系统代理
      libayatana-appindicator # 托盘图标
    ];
  };
}
