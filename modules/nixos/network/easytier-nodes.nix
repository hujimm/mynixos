# EasyTier 全网拓扑的【唯一事实来源】。
#
# 新增/迁移机器只改这一个文件；各 host 只需 import ../network 并写
#   my.easytier = { enable = true; node = "<key>"; };
# （node 默认取 networking.hostName，桌面因 hostName 是 mynixos 才需显式覆盖）
#
# 约束：nodes 的 key 必须与对应机器的 my.easytier.node 一致，且虚拟 IP 不能重复。
{
  # instance_name / network_name
  network = "ctmiop";

  # 虚拟网段（模块据此推导 ipv4 前缀）
  cidr = "10.144.144.0/24";

  # 有公网入口的锚点：其他节点的 peers 会自动指向这里的【全部】锚点。
  # key 是 nodes 里的节点名，值是它对外可达的 peer URL【列表】——
  # 一个锚点可写多个地址（如同时给 IPv4 与 IPv6），模块会全部展开。
  # 注意：aliyun 自己没有 IPv6，它连 lightsail 只能走 v4；lightsail 的 v6 条目
  # 是留给有公网 IPv6 的客户端（如手机）用的。
  # 每个锚点同时给 tcp 与 udp：udp 开销小、是打洞基础，tcp 更抗“封 UDP”的网络；
  # 两者都监听在 11010，写两条可提高直连成功率（官方也建议多写 peer）。
  anchors = {
    aliyun = [
      "tcp://114.215.126.192:11010"
      "udp://114.215.126.192:11010"
    ];
    # lightsail（AWS 悉尼）：公网 v4 + 公网 v6，各给 tcp/udp。地址若在停机/重启后
    # 变化需同步这里，长期当锚点建议在 Lightsail 控制台绑定静态 IP。
    lightsail = [
      "tcp://54.252.25.182:11010"
      "udp://54.252.25.182:11010"
      "tcp://[2406:da1c:803:3100:5d3e:e029:7a4a:f6c]:11010"
      "udp://[2406:da1c:803:3100:5d3e:e029:7a4a:f6c]:11010"
    ];
  };

  # 节点名 -> 虚拟 IP 末段（十进制）。
  # 目前：手机是 App（10.144.144.3），不进本表。
  nodes = {
    aliyun = 1;
    vostro-3420 = 2;
    lightsail = 5;
  };
}
