{
  description = "Orion's NixOS flake";

  nixConfig = {
    substituters = [
      # 3个国内大学镜像(tuna 只镜像活跃 channel 的部分路径,
      # 其他 nixpkgs rev 的依赖要 SJTU/USTC 才有,所以全开)
      #"https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store?priority=10"
      #"https://mirror.sjtu.edu.cn/nix-channels/store?priority=20"
      #"https://mirrors.ustc.edu.cn/nix-channels/store?priority=10"
      # 官方原站
      "https://cache.nixos.org?priority=40"
      # 社区缓存
      "https://nix-community.cachix.org?priority=45"
      # noctalia v5
      "https://noctalia.cachix.org?priority=50"
      # ayugram-desktop
      "https://ayugram-desktop.cachix.org?priority=50"
      # AyuGram 的 tg_owt 依赖
      "https://tg-owt.cachix.org?priority=50"
      # fcitx5-vinput 语音输入
      "https://fcitx5-vinput.cachix.org?priority=50"
      # hermes-agent（Tier 2，缓存未必每 rev 都有）
      "https://hermes-agent.cachix.org?priority=50"
      # llm-agents.nix（numtide 每日更新的 AI agent 包集合）
      "https://cache.numtide.com?priority=50"
      # deepseek-harness（dsh）Nix 打包缓存
      "https://deepseek-harness-nix.cachix.org?priority=50"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "ayugram-desktop.cachix.org-1:AZ5EqHrJsAKL5YkZYLPEsb1FdD9QlypUwQ0REcJftgA="
      "tg-owt.cachix.org-1:lp0BukIhSK3EIyLcDhDZ5zABgT48nmNp6t4SnZ0wr8w="
      "fcitx5-vinput.cachix.org-1:XpX3AA6+dDIX4qJhb1QM7sbTwX6/qSlGvW8Z5NK6XdU="
      # hermes-agent（Tier 2，缓存未必每 rev 都有；密钥经 GitHub 实配案例核实）
      "hermes-agent.cachix.org-1:jN3pjR50Mxi4SESKC/FIMNM6/LCosvPk2VUwzVvebzU="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      # deepseek-harness（dsh）Nix 打包缓存
      "deepseek-harness-nix.cachix.org-1:5NrkwLN9veNMhiINtU5ZeV4isXFhFsOwn6Ms7J1M+TA="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 密钥管理：sops 加密文件 + age 密钥，激活时解密到 /run/secrets
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
      #inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia Greeter(greetd 登录界面,与 Noctalia v5 配对使用)
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zen 浏览器(社区 flake)
    # 使用 beta 分支:仅在 beta 渠道更新时移动,不受 main 分支每日 twilight 更新干扰
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake/beta";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    # Spicetify(声明式包装 Spotify)
    # 文档:https://wiki.nixos.org/wiki/Spicetify-Nix
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AyuGram(Telegram 增强客户端,NixOS flake 打包)
    # README 要求 git 类型 + submodules,否则构建失败
    ayugram-desktop = {
      type = "git";
      submodules = true;
      url = "https://github.com/ndfined-crp/ayugram-desktop/";
    };

    # 锁定 v2.3.26：上游自 v2.3.5 起在发布 tag 时自动跑 nix-cache，
    # 该 tag 的构建已推送 fcitx5-vinput.cachix.org（nix-cache 2026-09-15 成功）。
    # 升级：上游发新 v* tag 且 nix-cache 跑完后，直接 pin 到新 tag，
    # 或改回 github:xifan2333/fcitx5-vinput 后跑 nix flake lock --update-input fcitx5-vinput。
    fcitx5-vinput = {
      url = "github:xifan2333/fcitx5-vinput/v2.3.26";
    };

    # 3.2.1 已发布并验证(2026-09-10):数据目录迁 com.ffclient.app、librust_api、
    # libsecret、schema 目录、GSETTINGS_SCHEMA_DIR 等适配点全部完成。
    # 升级:上游发新版本后先按其 AGENTS.md 升级流程处理,再 lock --update-input。
    flashfox-lite = {
      url = "github:liyinuo2006/flashfox-lite-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent = {
      # 钉到官方 release tag：v2026.9.21 = v0.21.4（2026-09-21 发布，滚动汇总版，
      # 含 state.db/profile 隔离等一批修复；v2026.9.14 = v0.21.3 的远程 gateway 登录
      # 与 state.db 写句柄泄漏修复也包含在内）。
      # 好处：只吃官方发布，不吃 main 上未发布的提交。
      url = "github:NousResearch/hermes-agent/v2026.9.21";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    deepseek-harness.url = "github:Moraxyc/deepseek-harness.nix";

    # disko：nixos-anywhere 依赖它做声明式分区（aliyun 云主机用，见 hosts/aliyun/）。
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Operit2 打包：独立 flake，按发布提交锁定。
    # 上游改动 push 后，用 `nix flake update operit2` 升级。
    operit2 = {
      url = "github:liyinuo2006/operit2-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cua-driver：Computer Use 后台桌面驱动（trycua/cua）。
    # 为何用 Nix 构建版而非官方 curl|bash 版：curl|bash 发布的二进制把
    # portal-libei（Wayland 输入）feature-gate 关掉了，在 niri（纯 Wayland）上
    # 只能看到代理光标、点击无法派发（trycua/cua issue #1982）。
    # Nix 包用 --features portal-input,portal-capture（== portal-libei）编入了
    # libei + pipewire，才支持 niri/Wayland 输入。
    # 保持独立 nixpkgs pin（上游锁 nixos-26.05），不 follow 根 nixpkgs——
    # 避免 nixos-unstable 的 libspa/libei 漂移破坏该构建；升级走
    # `nix flake lock --update-input cua`。
    cua.url = "github:trycua/cua";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    {
      nixosConfigurations.mynixos = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/vostro-3420
          home-manager.nixosModules.home-manager
        ];
      };

      # 阿里云 ECS 云主机（精简服务器系统，由 nixos-anywhere 安装）
      nixosConfigurations.aliyun = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/aliyun ];
      };

      # AWS Lightsail 云主机（就地 nixos-infect 安装，非 disko；见 hosts/lightsail/）
      nixosConfigurations.lightsail = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./hosts/lightsail ];
      };
    };
}
