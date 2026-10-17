{ ... }:
{
  # 组网模块：EasyTier 覆盖网（拓扑数据在同目录 easytier-nodes.nix）。
  # 独立于 programs/ 与 services/，供桌面与各云主机 host 共用。
  imports = [
    ./easytier.nix
  ];
}
