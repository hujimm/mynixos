# OpenClaw 的 Honcho 记忆插件打包（2026-10 弃用）。服务端在同级 server.nix。
#
# 不能走 nix-openclaw 的标准入口 runtimePluginSources：它会校验插件自带 bundled
# node_modules 或 npm-shrinkwrap.json（honcho 发布物两者都没有），且读的是 package.json
# 的 runtimeExtensions 而 honcho 写的是 openclaw.extensions。所以自己物化依赖、组装出
# install.mjs 认可的形状：包内容 + node_modules + openclaw peer 软链。
{ pkgs, lib ? pkgs.lib }:

let
  # 必须是 gateway 包：overlay 里的 pkgs.openclaw 只是薄包装，插件 peer 都链到
  # ${gateway}/lib/openclaw。
  gatewayPkg = pkgs.openclaw-gateway;
  honchoVersion = "1.7.0";

  honchoSrc = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@honcho-ai/openclaw-honcho/-/openclaw-honcho-${honchoVersion}.tgz";
    hash = "sha256-F1zkDsITr6j6armXJw02gZk+7CU122kOH1NOL4k3vgk=";
  };

  # FOD（允许联网）物化生产依赖，输出按 hash 钉死：上游依赖漂移会构建失败而不是静默变化。
  honchoDeps = pkgs.stdenvNoCC.mkDerivation {
    pname = "openclaw-honcho-deps";
    version = honchoVersion;
    dontUnpack = true;
    dontInstall = true;
    dontFixup = true;
    nativeBuildInputs = [
      pkgs.nodejs_24
      pkgs.cacert
    ];
    # 沙箱里没有 CA 库，node/npm 会报 UNABLE_TO_GET_ISSUER_CERT_LOCALLY。
    env = {
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      NODE_EXTRA_CA_CERTS = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-7VU6Zz6nzzbR1d67quxAS/s3wYxdoSAaulHz4xoBX20=";
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      export npm_config_cache=$TMPDIR/npm-cache
      mkdir -p $out
      tar -xzf ${honchoSrc} -C $out
      cd $out/package
      # 不解析 openclaw peer，运行时由下面的软链提供。
      npm install --omit=dev --omit=peer --legacy-peer-deps --ignore-scripts --no-audit --no-fund
      rm -rf node_modules/.bin
      runHook postBuild
    '';
  };

  honchoPlugin = pkgs.runCommand "openclaw-honcho-plugin-${honchoVersion}" { } ''
    cp -r ${honchoDeps}/package $out
    chmod -R u+w $out
    rm -rf $out/node_modules/.bin
    mkdir -p $out/node_modules
    ln -sfn ${gatewayPkg}/lib/openclaw $out/node_modules/openclaw
  '';
in
honchoPlugin
