# EasyTier 组网通用模块：把「每台机器一份完整配置」收敛成
# 「拓扑表（./easytier-nodes.nix）+ 每台一句 enable」。
#
# 每台 host 只需：
#   imports = [ ../../modules/nixos/network ];
#   my.easytier.enable = true;                 # node 默认取 networking.hostName
#   my.easytier.node = "vostro-3420";          # 需要覆盖网格显示名时才写
#
# 网络口令不进 Nix store：settings.network_secret 只写 ${ET_NETWORK_SECRET} 占位符，
# 由 sops 渲染的 EnvironmentFile（见 modules/nixos/security/easytier-secret.nix）在
# 运行时注入；easytier-core 读取 -c 配置文件时会展开 ${...}（未加 --disable-env-parsing）。
#
# 与两个代理 TUN 的共存：EasyTier 只为本网络网段建路由，一般不与闪狐(Meta)/Clash(Mihomo)
# 的全局 TUN 冲突；若 Clash auto-route 吞掉该网段，需在 Clash 侧给该网段加直连/绕过规则。
{ config, lib, ... }:

let
  topo = import ./easytier-nodes.nix;
  node = config.my.easytier.node;

  # 本机在拓扑里的虚拟 IP 末段；未登记则为 null（下面 assertion 拦截）
  ipSuffix = topo.nodes.${node} or null;
  # "10.144.144.0/24" -> "10.144.144"
  prefix = lib.removeSuffix ".0/24" topo.cidr;

  # peers：除自己以外的所有锚点
  peers = map (n: topo.anchors.${n}) (
    builtins.filter (n: n != node) (builtins.attrNames topo.anchors)
  );
in
{
  options.my.easytier = {
    enable = lib.mkEnableOption "EasyTier 组网（拓扑见 modules/nixos/network/easytier-nodes.nix）";

    node = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "本机在 easytier-nodes.nix 里的节点名，同时用作网格显示名。";
    };
  };

  config = lib.mkIf config.my.easytier.enable {
    assertions = [
      {
        assertion = ipSuffix != null;
        message = "EasyTier: 节点 \"${node}\" 未在 modules/nixos/network/easytier-nodes.nix 的 nodes 里登记虚拟 IP。";
      }
    ];

    services.easytier = {
      enable = true;

      instances.main = {
        environmentFiles = [ config.sops.templates."easytier-env".path ];

        settings = {
          instance_name = topo.network;
          hostname = node;
          network_name = topo.network;
          network_secret = "\${ET_NETWORK_SECRET}"; # 运行时展开，明文不落 store
          ipv4 = "${prefix}.${toString ipSuffix}/24";
          # listeners 用模块默认 tcp+udp 0.0.0.0:11010
          peers = peers;
        };

        extraSettings.flags = {
          accept_dns = true;
          private_mode = true;
        };
      };
    };

    # P2P 直连需要入站 11010（内网 NAT 后面的入站能否到达取决于路由器）
    networking.firewall.allowedTCPPorts = [ 11010 ];
    networking.firewall.allowedUDPPorts = [ 11010 ];
  };
}
