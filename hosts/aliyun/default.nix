# 阿里云 ECS 云主机：精简 NixOS（云主机基础 + SSH + 常用 CLI）。
# 由 nixos-anywhere 远程安装，磁盘布局见 ./disk-config.nix。
{
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ./sops.nix
    ./mcp-nixos.nix
    ../../modules/nixos/server
    ../../modules/nixos/network
    inputs.disko.nixosModules.disko
  ];

  # EasyTier 组网锚点：本机有公网 IP，作为中心节点，其余节点都连它。
  # 拓扑与虚拟 IP 见 modules/nixos/network/easytier-nodes.nix（本机 = aliyun，10.144.144.1）；
  # 网络口令由 sops 渲染为 EnvironmentFile（见 ./sops.nix）。
  # ECS 安全组需另行放行 TCP+UDP 11010。
  my.easytier.enable = true;

  networking.hostName = "aliyun";

  # 复用阿里云密钥对（私钥 ~/.ssh/aliyun.pem）。
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDnLPyOSX/kKEARUgBeGNbXej68d8akbLNxjPjGHWkjKYtY/iVEZFK6wYIpSUWH2WJadwEfQflYuAMQcdho++zTEXbjHS6PFT0QCElMR491VvTmqnNIBSSzh6D9ZUjTamBqD9rHXQSIQNhYYMdZoMLj6MIxFzG+Qebeo/2HKdhS9D+dgpA/ymsvMf4CXUrViGpXT3DmIhN7WWEmyz/5LJRy2XlB1P61FI/4lWL9YEmn2PSeIEUn1N9i5g1ozd+DGO/xVh7pBCvv7ynJc+3hxjue44JsuyIUZMEwwkRWuoso3y0lN/icmxfT2yGSXyqr2FT6MuAl70FgLVeAYRzGthij aliyun-ecs"
  ];

  # KVM 客机：启用 qemu-guest-agent。
  services.qemuGuest.enable = true;

  system.stateVersion = "26.05";
}
