# AWS Lightsail 就地安装配置（供 nixos-infect 使用）。
#
# 为什么不用 nixos-anywhere / disko：Lightsail 是 Nitro 平台，kexec 后 ENA/NVMe
# 设备不重新初始化（nixos-anywhere issue #139），会失联；且 Lightsail 不支持导入
# 自定义镜像。故采用 nixos-infect 的 lustrate「就地替换」（普通重启，设备正常复位）。
#
# 为什么自带配置：nixos-infect 的 lightsail 预设只 import amazon-image.nix，
# 而 ec2.efi 默认值 = isAarch64（x86_64 上为 false），会装 BIOS GRUB —— 对这台
# UEFI 机器是致命的。这里显式写 UEFI：ESP 挂 /boot/efi、可移动回退路径，
# 与 nixos-infect 的 EFI 收尾（它把 ESP 挂到 /boot/efi）一致，也与当前 Ubuntu 布局一致。
#
# 本文件同时被 hosts/lightsail/default.nix 作为 flake host 复用，所以自包含
# （不依赖 flake inputs、不使用 disko）。
{
  lib,
  pkgs,
  ...
}:

{
  # 引导：UEFI + 可移动回退路径（EFI/BOOT/BOOTX64.EFI）；ESP 在 /boot/efi，内核放独立 /boot
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # 【仅就地安装时需要放开】关闭 systemd-initrd，让 nixos-infect 的 lustrate 生效：
  # NixOS 26.05 起 boot.initrd.systemd.enable 默认为 true，而 NIXOS_LUSTRATE
  # （首次启动把旧系统整体挪到 /old-root）只在【bash 版 stage-1】（stage-1-init.sh
  # 的 lustrateRoot）里实现，systemd-initrd 完全没有这段逻辑。首次启动若没关，
  # 旧 Ubuntu 的 /etc、/usr 不会被挪走，其 systemd 单元（systemd-networkd/resolved/
  # dbus 等）会泄漏进来、网络起不来——即"装完重启就失联"（已在 EC2 串口日志实锤）。
  #
  # 但 lustrate 只发生一次：本机装好后新根上已无 /etc/NIXOS_LUSTRATE（清单归档在
  # /old-root/），不会再跑。故这里默认注释掉，日常用系统默认的 systemd-initrd
  # （顺带免掉 26.11 移除脚本式 initrd 的弃用警告）。
  # ⚠️ 若要用本文件【重装新机】（nixos-infect 就地安装），务必先把下面这行放开：
  # boot.initrd.systemd.enable = false;

  # 磁盘按 UUID 引用（nixos-infect 会把根分区 relabel 成 nixos，UUID 不变）
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/d662a37e-da8d-4720-94ff-f588450178c0";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/71a1f8dc-6e9a-4e94-bf6b-9b1ea9866c4b";
    fsType = "ext4";
  };
  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/876F-1C6F";
    fsType = "vfat";
    # 与真机 nixos-generate-config 的输出一致（vfat 默认权限）
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # AWS Nitro（NVMe + ENA）
  boot.initrd.availableKernelModules = [
    "nvme"
    "ena"
    "virtio_pci"
    "virtio_blk"
    "sd_mod"
    "uas"
  ];
  boot.initrd.kernelModules = [ "nvme" ];
  boot.kernelParams = [
    "nvme_core.io_timeout=4294967295"
    "random.trust_cpu=on"
    "console=ttyS0,115200n8"
  ];

  # 平台（真机 nixos-generate-config 亦会写上，这里补上保持一致）
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking.hostName = "lightsail";
  networking.useDHCP = lib.mkDefault true;
  time.timeZone = "Asia/Shanghai";

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # 复用 AWS 密钥对（私钥 /home/orion/下载/aws-nix.pem）
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRuGFB5F6SHRHgTWG7ne5op18rCBqqNrZF6IPX8JHEUknWu84KaT8E6NfZQiGfgYBL6n7uTpqCqxNl8C0UKGAJcR9S3SR4laUzBwbu0sWs+xc0IStvbfEp/gSMNuo0rSAHM7aEoKVKgmBCYWCENdqGOeP247e0xK+JkFAuNfvtgm3HDekSCuYt8TmUD2pkINes4DJRCtI/lkbfFjqOPW3FvOvxjWxaQ4yWcqI9lwREMGx4RkP4MRH6/B1xFIHu6HwizMC2fkxxgmlJ3YuM+1GERE5ehfWcoYVjIH27vtvDKxnaz7ls00Xp+HF0K7IW6JjzaD2jyaOHE+P2IHpOIaCN aws-nix"
  ];

  # Lightsail 浏览器 SSH 默认以 ubuntu 用户登录；建一个同名用户当"健康探针"，
  # 这样控制台的 Connect using SSH 能真连进来（NixOS 默认没有 ubuntu 用户）。
  users.users.ubuntu = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRuGFB5F6SHRHgTWG7ne5op18rCBqqNrZF6IPX8JHEUknWu84KaT8E6NfZQiGfgYBL6n7uTpqCqxNl8C0UKGAJcR9S3SR4laUzBwbu0sWs+xc0IStvbfEp/gSMNuo0rSAHM7aEoKVKgmBCYWCENdqGOeP247e0xK+JkFAuNfvtgm3HDekSCuYt8TmUD2pkINes4DJRCtI/lkbfFjqOPW3FvOvxjWxaQ4yWcqI9lwREMGx4RkP4MRH6/B1xFIHu6HwizMC2fkxxgmlJ3YuM+1GERE5ehfWcoYVjIH27vtvDKxnaz7ls00Xp+HF0K7IW6JjzaD2jyaOHE+P2IHpOIaCN aws-nix"
    ];
  };

  # 内存 ~1.9GiB，加 2GiB swapfile（与 nixos-infect 的 /tmp 临时 swap 不冲突）
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 2048;
    }
  ];

  # 【内存】zswap：给上面的 swapfile 做前端压缩缓存。
  # 内核要换出一页时先把它压进 RAM（zstd，压缩比通常 2–3:1），池满才真写盘；
  # 回读是解压而不是磁盘 I/O。和 swapDevices 是配套关系而非二选一——
  # nixpkgs 的 boot.zswap 模块自带两条断言兜底：必须至少有一个 swapDevices，
  # 且不能与 zramSwap 同开（双重压缩）。
  #
  # maxPoolPercent 是**上限**不是预留：池按需增长，不换页就不占内存。
  # nixpkgs 文档的参考是「服务器 10–20%、低内存机 30–50%」；本机 1.9GiB 属
  # 低内存，取 30%（约 570MB 上限），让更多换出页以压缩态留在 RAM、少写盘；
  # 池满或内存吃紧时由 shrinker（默认开启）回收。
  boot.zswap = {
    enable = true;
    maxPoolPercent = 30;
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
    # 只保留官方源：本机只用 nixpkgs 包，不需要社区 cachix 缓存。
    substituters = [
      "https://cache.nixos.org"
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

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  system.stateVersion = "26.05";
}
