# libvirt + virt-manager（KVM，2026-09 弃用）。
{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      # 共享文件夹需要 virtiofsd。
      vhostUserPackages = [ pkgs.virtiofsd ];
      # Windows 11 之类需要 TPM 的来宾才用得上。
      swtpm.enable = true;
    };
  };

  programs.virt-manager.enable = true;

  virtualisation.spiceUSBRedirection.enable = true;

  # 默认网络 virbr0 的 DNS/DHCP 由 dnsmasq 提供，缺了默认网络起不来。
  environment.systemPackages = [ pkgs.dnsmasq ];
}
