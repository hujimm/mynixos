# OpenClaw 官方 Linux 桌面端（Tauri 壳，2026-10 弃用）。
#
# 上游只发 .deb / .AppImage，nixpkgs 里没有，这里套 appimageTools.wrapType2 自己包。
# 升级改 version + hash，校验和在同 tag 的 SHA256SUMS.linux-app.txt。
#
# 三个坑：本 nixpkgs 里 pkgs.makeWrapper 只有 setup-hook、没有 bin/makeWrapper，所以启动
# 脚本用 writeShellScript 写；exec 的路径必须带 /bin（.openclaw-desktop-unwrapped）；
# AppImage 的 apprun-hook 强制 GDK_BACKEND=x11 并覆盖 GTK_PATH/GTK_IM_MODULE_FILE
# （自带 immodules.cache 没有 im-fcitx5.so），只能走 XIM，且 XMODIFIERS 只写进
# hm-session-vars.sh（登录 shell 才 source），启动器起的应用拿不到，必须在包装层写死。
{
  pkgs,
  lib,
  ...
}:
let
  pname = "openclaw-desktop";
  version = "2026.10.4";
  src = pkgs.fetchurl {
    url = "https://github.com/openclaw/openclaw/releases/download/v${version}/OpenClaw-${version}-amd64.AppImage";
    hash = "sha256-0NMZj824fCN5n2DIJJLd1/JoA3rw6ytaKCeY+3+l73Q=";
  };
  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };

  launcher = pkgs.writeShellScript "${pname}-launcher" ''
    export XMODIFIERS='@im=fcitx'
    export GTK_IM_MODULE=xim
    exec "@OUT@/bin/.openclaw-desktop-unwrapped" "$@"
  '';
in
{
  environment.systemPackages = [
    (pkgs.appimageTools.wrapType2 {
      inherit pname version src;

      # wrapType2 不会装 AppImage 里的桌面项与图标。
      extraInstallCommands = ''
        install -Dm444 ${appimageContents}/usr/share/applications/OpenClaw.desktop \
          "$out/share/applications/openclaw-desktop.desktop"
        substituteInPlace "$out/share/applications/openclaw-desktop.desktop" \
          --replace-fail "Exec=openclaw-desktop" "Exec=$out/bin/openclaw-desktop"

        for size in 16x16 32x32 64x64 128x128 256x256 256x256@2 512x512; do
          icon="${appimageContents}/usr/share/icons/hicolor/$size/apps/openclaw-desktop.png"
          [ -f "$icon" ] && install -Dm444 "$icon" \
            "$out/share/icons/hicolor/$size/apps/openclaw-desktop.png"
        done

        mv "$out/bin/openclaw-desktop" "$out/bin/.openclaw-desktop-unwrapped"
        install -Dm755 ${launcher} "$out/bin/openclaw-desktop"
        substituteInPlace "$out/bin/openclaw-desktop" \
          --replace-fail '@OUT@' "$out"
      '';

      meta = {
        description = "OpenClaw Linux companion desktop application";
        homepage = "https://github.com/openclaw/openclaw";
        license = lib.licenses.mit;
        platforms = [ "x86_64-linux" ];
        mainProgram = pname;
        sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      };
    })
  ];
}
