{
  pkgs,
  inputs,
  ...
}:
let
  wechat-wrapped = pkgs.symlinkJoin {
    name = "${pkgs.wechat.pname or "wechat"}-${pkgs.wechat.version}";
    paths = [ pkgs.wechat ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/wechat \
        --set QT_QPA_PLATFORM xcb \
        --set QT_IM_MODULE fcitx \
        --set GTK_IM_MODULE fcitx \
        --set QT_AUTO_SCREEN_SCALE_FACTOR 1
    '';
  };

  wps-wrapped = pkgs.symlinkJoin {
    name = "${pkgs.wpsoffice-cn.pname or "wpsoffice-cn"}-${pkgs.wpsoffice-cn.version}";
    paths = [ pkgs.wpsoffice-cn ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for bin in wps wpp et wpspdf; do
        wrapProgram $out/bin/$bin \
          --set QT_QPA_PLATFORM xcb \
          --set QT_FONT_DPI 144 \
          --set QT_IM_MODULE fcitx \
          --set GTK_IM_MODULE fcitx \
          --set XMODIFIERS @im=fcitx
      done
    '';
  };

in

{
  home.packages = with pkgs; [

    wechat-wrapped
    qq
    wps-wrapped
    google-chrome

    nautilus
    rayburst

    # Noctalia 模板主题依赖:GTK 基础主题 + Qt 配色工具
    adw-gtk3
    qt6Packages.qt6ct

    ripgrep
    tree
    btop
    fastfetch
    rsync

    # Node.js 生态:pnpm 替代 npm(避免 npm 11 处理大型依赖图卡死),
    # 加上编译原生模块(node-pty/koffi 等)所需工具链。
    nodejs
    pnpm
    gcc
    gnumake
    # python3 兼作 node-gyp 编译依赖;withPackages 附赠 pip/virtualenv,
    # 项目内用 python -m venv 装包最稳,不依赖系统 rebuild
    (python3.withPackages (ps: [
      ps.pip
      ps.virtualenv
    ]))
    pkg-config
    node-gyp
    cmake
    #压缩与解压缩
    unzip
    zip
    p7zip
    # rar 包同时提供 rar 与 unrar 命令，无需单独装 unrar
    rar
    gnutar
    gzip
    xz
    bzip2
    swayimg
    nautilus-python

    #视频工具
    ffmpeg-full
    mpv
    obs-studio
    yt-dlp
    mediainfo

    jq # JSON 处理/格式化,管道解析接口返回或日志
    yq-go # YAML 处理(Go 版 mikefarah/yq;注意 nixpkgs 的 yq 是 Python 版)
    file # 识别文件真实类型(压缩包/二进制/文本)
    sqlite # SQLite 命令行,查询 .db 文件(nixpkgs 属性名是 sqlite,命令是 sqlite3)
    socat # 端口转发/双向数据流,网络调试利器(nc 的增强版)

    # 可选:提升命令行体验
    fd # find 的现代替代,按文件名快速搜索
    fzf # 终端模糊搜索,可与 fd/命令历史联动
    bat # cat 替代,带语法高亮与行号
    eza # ls 替代,彩色输出/图标/树形
    direnv # 进入目录自动加载 .envrc/flake devShell 环境
    htop # 进程监控(与 btop 二选一,按习惯保留)
    nix-output-monitor # nix build 输出实时监控(nom:下载/构建进度总览,配合 nixos-rebuild 管道使用)
    ncdu # 磁盘占用交互式分析
    tmux # 终端复用,会话保持/分屏
    pciutils # lspci 等 PCI 硬件信息
    usbutils # lsusb 等 USB 设备信息
    gdb # C/C++ 程序调试器
    ltrace # 跟踪程序库调用(strace 已由系统提供)
    openssl

    # AyuGram:Telegram 增强客户端(Ghost Mode、防撤回等)
    inputs.ayugram-desktop.packages.${pkgs.stdenv.hostPlatform.system}.ayugram-desktop

  ];
}
