{
  pkgs,
  lib,
  ...
}:
# OpenClaw 官方 Linux 桌面端（Tauri 壳，连接网关，含 Control UI / 托盘 / Quick Chat）。
#
# 包法照抄 not-matthias/dotfiles-nix 的 pkgs/openclaw.nix：直接用上游是 release 里的
# AppImage，套 appimageTools.wrapType2；hash 与官方 SHA256SUMS.linux-app.txt 逐字节一致。
# 上游 Linux 桌面端只发 .deb / .AppImage，nixpkgs、nix-openclaw、llm-agents.nix 都没有，
# 所以这份是唯一现成的 Nix 包装，自包含、不引新 flake input。
#
# 升级：改下面的 version + hash（源固定是同 tag 的 OpenClaw-<version>-amd64.AppImage）。
# 官方校验和：https://github.com/openclaw/openclaw/releases/download/v<version>/SHA256SUMS.linux-app.txt
let
  pname = "openclaw-desktop";
  version = "2026.10.4";
  src = pkgs.fetchurl {
    url = "https://github.com/openclaw/openclaw/releases/download/v${version}/OpenClaw-${version}-amd64.AppImage";
    hash = "sha256-0NMZj824fCN5n2DIJJLd1/JoA3rw6ytaKCeY+3+l73Q=";
  };
  appimageContents = pkgs.appimageTools.extractType2 { inherit pname version src; };
in
{
  environment.systemPackages = [
    (pkgs.appimageTools.wrapType2 {
      inherit pname version src;

      # wrapType2 不会装 AppImage 里的桌面项与图标，这里补上（条目名与图标名
      # 都按上游 Tauri 产物：OpenClaw.desktop / openclaw-desktop.png）。
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
