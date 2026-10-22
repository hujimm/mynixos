# AWS Lightsail host（nixosConfigurations.lightsail）。
# 硬件与文件系统见 ./hardware.nix；云主机共用基础见 modules/nixos/server；
# ./sops.nix、./vaultwarden.nix 是这台机器专有的服务。
{ ... }:

let
  # AWS 密钥对（私钥 /home/orion/下载/aws-nix.pem），root 与控制台 ubuntu 用户共用。
  awsKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRuGFB5F6SHRHgTWG7ne5op18rCBqqNrZF6IPX8JHEUknWu84KaT8E6NfZQiGfgYBL6n7uTpqCqxNl8C0UKGAJcR9S3SR4laUzBwbu0sWs+xc0IStvbfEp/gSMNuo0rSAHM7aEoKVKgmBCYWCENdqGOeP247e0xK+JkFAuNfvtgm3HDekSCuYt8TmUD2pkINes4DJRCtI/lkbfFjqOPW3FvOvxjWxaQ4yWcqI9lwREMGx4RkP4MRH6/B1xFIHu6HwizMC2fkxxgmlJ3YuM+1GERE5ehfWcoYVjIH27vtvDKxnaz7ls00Xp+HF0K7IW6JjzaD2jyaOHE+P2IHpOIaCN aws-nix";
in
{
  imports = [
    ./hardware.nix
    ./nginx.nix
    ./sops.nix
    ./vaultwarden.nix
    ../../modules/nixos/server
    ../../modules/nixos/network
  ];

  networking.hostName = "lightsail";

  users.users.root.openssh.authorizedKeys.keys = [ awsKey ];

  # Lightsail 浏览器 SSH 默认以 ubuntu 用户登录；建一个同名用户当“健康探针”，
  # 这样控制台的 Connect using SSH 能真连进来（NixOS 默认没有 ubuntu 用户）。
  users.users.ubuntu = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ awsKey ];
  };

  # EasyTier 组网：拓扑与虚拟 IP 见 modules/nixos/network/easytier-nodes.nix
  # （本机 = lightsail，10.144.144.5）。
  my.easytier.enable = true;

  system.stateVersion = "26.05";
}
