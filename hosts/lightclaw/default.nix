# AWS Lightsail host（nixosConfigurations.lightclaw）。t3.medium、悉尼、80G 盘。
# 硬件与文件系统见 ./hardware.nix；云主机共用基础见 modules/nixos/server。
# 这台机器跑一个 OpenClaw 网关（Home Manager 用户服务，见 ./openclaw.nix），密钥经 ./sops.nix 解密。
{ inputs, ... }:

let
  # AWS 密钥对（私钥 ~/.ssh/aws-nix.pem），与 lightsail 同一把；
  # root 与控制台 ubuntu 用户共用。
  awsKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRuGFB5F6SHRHgTWG7ne5op18rCBqqNrZF6IPX8JHEUknWu84KaT8E6NfZQiGfgYBL6n7uTpqCqxNl8C0UKGAJcR9S3SR4laUzBwbu0sWs+xc0IStvbfEp/gSMNuo0rSAHM7aEoKVKgmBCYWCENdqGOeP247e0xK+JkFAuNfvtgm3HDekSCuYt8TmUD2pkINes4DJRCtI/lkbfFjqOPW3FvOvxjWxaQ4yWcqI9lwREMGx4RkP4MRH6/B1xFIHu6HwizMC2fkxxgmlJ3YuM+1GERE5ehfWcoYVjIH27vtvDKxnaz7ls00Xp+HF0K7IW6JjzaD2jyaOHE+P2IHpOIaCN aws-nix";
in
{
  imports = [
    ./hardware.nix
    ./sops.nix
    ./nginx.nix
    ../../modules/nixos/server
    ../../modules/nixos/network
  ];

  networking.hostName = "lightclaw";

  # 手机 App 连网关用：网关仍只绑回环，外网经 nginx(443, Cloudflare Origin CA 证书) 反代过去，
  # 见 ./nginx.nix。所以这里**不再**对 tun0 放行 18789（那道口子已撤）。
  # 令牌走 sops（openclaw-gateway-token）。

  # EasyTier 组网：拓扑与虚拟 IP 见 modules/nixos/network/easytier-nodes.nix
  # （本机 = lightclaw，10.144.144.6）。
  my.easytier.enable = true;

  users.users.root.openssh.authorizedKeys.keys = [ awsKey ];

  # Lightsail 浏览器 SSH 默认以 ubuntu 用户登录；建一个同名用户当“健康探针”，
  # 这样控制台的 Connect using SSH 能真连进来（NixOS 默认没有 ubuntu 用户）。
  users.users.ubuntu = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ awsKey ];
  };

  # nix-openclaw 的 overlay（提供 pkgs.openclaw；Home Manager 因 useGlobalPkgs 继承）。
  nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];

  # ---- OpenClaw 运行用户 ----
  # 专用普通用户：非 root（常驻进程攻击面小），但给免密 sudo 让 agent 能管理系统；
  # linger 让 systemd 用户服务在开机时启动（无交互登录也常驻）。
  users.users.openclaw = {
    isNormalUser = true;
    home = "/home/openclaw";
    linger = true;
  };
  security.sudo.extraRules = [
    {
      users = [ "openclaw" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # ---- Home Manager：为 openclaw 用户配置 OpenClaw 网关 ----
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  # nix-openclaw 的 Home Manager 模块（提供 programs.openclaw），对所有用户共享。
  home-manager.sharedModules = [ inputs.nix-openclaw.homeManagerModules.openclaw ];
  home-manager.users.openclaw = ./openclaw.nix;

  system.stateVersion = "26.05";
}
