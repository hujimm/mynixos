# 阿里云 ECS 云主机：精简 NixOS（基础系统 + SSH + 常用 CLI）。
# 由 nixos-anywhere 远程安装，磁盘布局见 ./disk-config.nix。
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ./astrbot.nix
    ./sops.nix
    ./mcp-nixos.nix
    inputs.disko.nixosModules.disko
  ];

  # EasyTier 组网锚点：本机有公网 IP，作为中心节点，本机与手机都连它。
  # 网络口令由 sops 渲染为 EnvironmentFile（见 ./sops.nix）。
  # 固定 IP .1，无 peers；listeners 用模块默认 tcp+udp 0.0.0.0:11010。
  services.easytier.enable = true;

  services.easytier.instances.main = {
    environmentFiles = [ config.sops.templates."easytier-env".path ];

    settings = {
      instance_name = "ctmiop";
      hostname = "aliyun";
      network_name = "ctmiop";
      network_secret = "\${ET_NETWORK_SECRET}"; # 运行时展开，明文不落 store
      ipv4 = "10.144.144.1/24";
    };

    extraSettings.flags = {
      accept_dns = true;
      private_mode = true;
    };
  };

  # NixOS 防火墙放行 EasyTier 监听端口；ECS 安全组需另行放行 TCP+UDP 11010。
  networking.firewall.allowedTCPPorts = [ 11010 ];
  networking.firewall.allowedUDPPorts = [ 11010 ];

  networking.hostName = "aliyun";
  # 阿里云 VPC 走 DHCP，公网 IP 由 NAT 映射，无需 cloud-init 配网。
  networking.useDHCP = lib.mkDefault true;
  time.timeZone = "Asia/Shanghai";

  # UEFI + 云上 NVRAM 可能不持久：用可移动回退路径 EFI/BOOT/BOOTX64.EFI。
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  services.openssh = {
    enable = true;
    settings = {
      # 仅密钥登录 root，关闭密码/交互认证
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # 复用阿里云密钥对（私钥 ~/.ssh/aliyun.pem），装完后仍可用它登录。
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDnLPyOSX/kKEARUgBeGNbXej68d8akbLNxjPjGHWkjKYtY/iVEZFK6wYIpSUWH2WJadwEfQflYuAMQcdho++zTEXbjHS6PFT0QCElMR491VvTmqnNIBSSzh6D9ZUjTamBqD9rHXQSIQNhYYMdZoMLj6MIxFzG+Qebeo/2HKdhS9D+dgpA/ymsvMf4CXUrViGpXT3DmIhN7WWEmyz/5LJRy2XlB1P61FI/4lWL9YEmn2PSeIEUn1N9i5g1ozd+DGO/xVh7pBCvv7ynJc+3hxjue44JsuyIUZMEwwkRWuoso3y0lN/icmxfT2yGSXyqr2FT6MuAl70FgLVeAYRzGthij aliyun-ecs"
  ];

  # 内存偏紧（~1.8GiB），加 2GiB swapfile 兜底，避免构建/运行 OOM。
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 2048;
    }
  ];

  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  # 缓存硬编码（与 modules/nixos/core/nix.nix 一致），只保留官方源：
  # 本机只用 nixpkgs 包（mcp-nixos、easytier 等），不涉及社区 cachix 缓存。
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [
      "https://cache.nixos.org?priority=40"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
    auto-optimise-store = false;
  };

  # 定期回收 store，避免 40G 系统盘被历史 generation 撑满。
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  system.stateVersion = "26.05";
}
