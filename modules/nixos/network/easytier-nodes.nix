# EasyTier 全网拓扑的唯一事实来源。新增/迁移机器只改这里。
# 约束：nodes 的键必须与对应机器的 my.easytier.node 一致，且虚拟 IP 不能重复。
{
  network = "ctmiop";
  cidr = "10.144.144.0/24";

  # 锚点：其他节点的 peers 会自动指向这里的全部锚点。
  # 值是 URL 列表，可同时写 v4/v6、tcp/udp。
  anchors = {
    aliyun = [
      "tcp://114.215.126.192:11010"
      "udp://114.215.126.192:11010"
    ];
    # lightsail（AWS 悉尼）：公网 v4 + v6。地址若变化需同步这里，长期当锚点建议绑静态 IP。
    lightsail = [
      "tcp://54.252.25.182:11010"
      "udp://54.252.25.182:11010"
      "tcp://[2406:da1c:803:3100:5d3e:e029:7a4a:f6c]:11010"
      "udp://[2406:da1c:803:3100:5d3e:e029:7a4a:f6c]:11010"
    ];
  };

  # 节点名 -> 虚拟 IP 末段。手机是 App（10.144.144.3），不进本表。
  nodes = {
    aliyun = 1;
    vostro-3420 = 2;
    lightsail = 5;
  };
}
