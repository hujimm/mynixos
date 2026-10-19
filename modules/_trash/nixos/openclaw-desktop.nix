# ============================================================================
# 【已弃用 · 2026-10-19】桌面笔记本上的 OpenClaw 官方 Linux 桌面端（仅存档）
# ============================================================================
#
# 状态：已停用、从构建中摘除（主人只当玩一下，不再用 OpenClaw）。
# 归档前它挂在 modules/nixos/programs/default.nix 的聚合器里，只装给桌面 host。
#
# 恢复：  git mv modules/_trash/nixos/openclaw-desktop.nix modules/nixos/programs/openclaw-desktop.nix
#         在 modules/nixos/programs/default.nix 的 imports 里加回 ./openclaw-desktop.nix
#
# 归档时踩过的两个坑（恢复后别再踩）：
#   1) nixpkgs 里 pkgs.makeWrapper 只有 setup-hook、没有 bin/makeWrapper → 直接用
#      writeShellScript 写启动脚本（本文件已改成这样）。
#   2) launcher 里 exec 的路径必须带 /bin：$out/bin/.openclaw-desktop-unwrapped。
#
# 输入法：AppImage 的 apprun-hook 强制 GDK_BACKEND=x11 且覆盖 GTK_PATH/
#   GTK_IM_MODULE_FILE（自带的 immodules.cache 无 im-fcitx5.so），故走 XIM
#   （XMODIFIERS=@im=fcitx + GTK_IM_MODULE=xim），并写死在包装层——因为
#   XMODIFIERS 只在 hm-session-vars.sh（登录 shell），启动器起的应用拿不到。
#
# ---------------------------------------------------------------------------
# 以下是停用前的原始内容
# ---------------------------------------------------------------------------
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
  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };

  # 启动包装（见 extraInstallCommands 里的说明）：AppImage 的 apprun-hook 强制
  # GDK_BACKEND=x11，并无条件覆盖 GTK_PATH / GTK_IM_MODULE_FILE（自带的
  # immodules.cache 里没有 im-fcitx5.so），所以走 XIM：GTK_IM_MODULE=xim +
  # XMODIFIERS=@im=fcitx，由 fcitx5 的 xim 前端接管（AppImage 自带 im-xim.so）。
  #
  # 为什么非要在包装层写死：XMODIFIERS 只由 HM 写进 hm-session-vars.sh（登录 shell
  # 才 source），`systemctl --user show-environment` 里没有 → 从桌面启动器点起来的
  # 应用拿不到，只有终端启动的才有。
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

        # ---- 输入法（fcitx5）----
        # 这个 AppImage 的 apprun-hook（linuxdeploy-plugin-gtk.sh）会**无条件**覆盖
        # GTK_PATH 与 GTK_IM_MODULE_FILE，指向自带的 immodules.cache，而那份 cache 里
        # 只有 xim/wayland/cedilla… 没有 im-fcitx5.so —— 所以 GTK_IM_MODULE=fcitx 在
        # 沙箱内走不通。它同时强制 GDK_BACKEND=x11（Tauri 在 Wayland 下的 workaround），
        # 因此正确路线是 XIM：GTK_IM_MODULE=xim + XMODIFIERS=@im=fcitx。这两个变量
        # apprun-hook 不碰，而 bwrap 不做 --clearenv，包装层的变量能原样进沙箱。
        #
        # 不用 makeWrapper：本 nixpkgs 里 pkgs.makeWrapper 只有 setup-hook，没有
        # bin/makeWrapper（构建时会 127），所以直接用自己写的 launcher 脚本。
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
