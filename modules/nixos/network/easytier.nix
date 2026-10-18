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

  # 除自己以外的所有锚点 URL（每个锚点可含多个 URL，如 v4+v6）
  allPeers = lib.concatMap (n: topo.anchors.${n}) (
    builtins.filter (n: n != node) (builtins.attrNames topo.anchors)
  );
  # v6 URL 形如 tcp://[2406:...]:11010。本机没有 IPv6 路由时（my.easytier.ipv6 = false）
  # 把它们从 peers 里去掉——否则 easytier 会每秒对 v6 地址反复拨号失败，刷爆 journal。
  peers =
    if config.my.easytier.ipv6 then
      allPeers
    else
      builtins.filter (u: !(lib.hasInfix "[" u)) allPeers;
in
{
  options.my.easytier = {
    enable = lib.mkEnableOption "EasyTier 组网（拓扑见 modules/nixos/network/easytier-nodes.nix）";

    node = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "本机在 easytier-nodes.nix 里的节点名，同时用作网格显示名。";
    };

    ipv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        是否把锚点里的 IPv6 地址加入 peers。本机没有 IPv6 路由时设为 false，
        避免对 v6 地址反复拨号失败。只影响本机，不改动拓扑表。
      '';
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
