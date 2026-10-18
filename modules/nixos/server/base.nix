# 云主机（aliyun / lightsail）共用的基础配置。
# 只放两台完全一致的部分；磁盘、内核模块、SSH 公钥等 host 特有的内容留在 hosts/。
{ lib, pkgs, ... }:

{
  # 两台都是 UEFI 云主机，装在可移动回退路径 EFI/BOOT/BOOTX64.EFI。
  # ESP 挂载点不同（aliyun 是 /boot，lightsail 是 /boot/efi），由各 host 自己设置。
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  # 两台内存都约 1.8GiB：2GiB swapfile + zswap 做前端压缩。
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 2048;
    }
  ];
  boot.zswap = {
    enable = true;
    maxPoolPercent = 30;
  };

  # 仅允许密钥登录 root，关闭密码与交互式认证。
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  networking.useDHCP = lib.mkDefault true;
  time.timeZone = "Asia/Shanghai";

  # 限制 journald：这些机器盘小，且历史上被刷屏过（aliyun 曾因 easytier 对 v6 地址
  # 反复拨号失败，把 journal 撑到 775MB、journald 内存 702MB）。设上限后一起回落。
  services.journald.settings.Journal = {
    SystemMaxUse = "150M";
    SystemMaxFileSize = "50M";
    MaxRetentionSec = "2week";
  };

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # 只用官方缓存（单源时 priority 无意义，故不写）。
    substituters = [ "https://cache.nixos.org" ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
    auto-optimise-store = false;
  };

  # 定期回收 store，避免小系统盘被历史 generation 撑满。
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;
}
