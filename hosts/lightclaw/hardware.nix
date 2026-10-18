# AWS Lightsail（lightclaw，t3.medium，悉尼）硬件描述，日常重建用。
# 由 nixos-infect 就地安装（同 lightsail），装机用的单文件配置在单独仓库维护，不在本仓库。
#
# 磁盘按 UUID 引用。注意：本机与 lightsail 出自同一 AMI 快照，三个分区的 UUID/PARTUUID
# 与 lightsail **完全相同**（见 hosts/lightsail/hardware.nix），故此处挂载点一致。
{ lib, ... }:

{
  # ESP 在 /boot/efi，内核放独立的 /boot
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

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

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
