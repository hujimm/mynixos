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
  # key 是 nodes 里的节点名，值是它对外可达的 peer URL。
  anchors = {
    aliyun = "tcp://114.215.126.192:11010";
  };

  # 节点名 -> 虚拟 IP 末段（十进制）。
  # 目前：手机是 App（10.144.144.3），不进本表。
  nodes = {
    aliyun = 1;
    vostro-3420 = 2;
    lightsail = 5;
  };
}
