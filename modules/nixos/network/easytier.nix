# EasyTier 组网通用模块：拓扑表（./easytier-nodes.nix）+ 每台 host 一句 enable。
#
# 每台 host：
#   imports = [ ../../modules/nixos/network ];
#   my.easytier.enable = true;                 # node 默认取 networking.hostName
#   my.easytier.node = "vostro-3420";          # 网格显示名与 hostName 不一致时才写
#
# 网络口令不进 Nix store：network_secret 写 ${ET_NETWORK_SECRET} 占位符，由 sops 渲染的
# EnvironmentFile（modules/nixos/security/easytier-secret.nix）在运行时注入。
{ config, lib, ... }:

let
  topo = import ./easytier-nodes.nix;
  node = config.my.easytier.node;

  # 本机虚拟 IP 末段；未登记为 null（下面 assertion 拦截）
  ipSuffix = topo.nodes.${node} or null;
  # "10.144.144.0/24" -> "10.144.144"
  prefix = lib.removeSuffix ".0/24" topo.cidr;

  # 除自己以外的所有锚点（每个锚点可含多个 URL，如 v4+v6）
  peers = lib.concatMap (n: topo.anchors.${n}) (
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
