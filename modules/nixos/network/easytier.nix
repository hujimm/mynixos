# ═══════════════════════════════════════════════════════════════════════════
# EasyTier 组网 · 通用模块
# ═══════════════════════════════════════════════════════════════════════════
# 目的：把「每台机器写一份完整的 EasyTier 配置」收敛成
#       「全网拓扑表（./easytier-nodes.nix）+ 每台机器一句 my.easytier.enable = true;」
#
# 每台 host 的 default.nix 里只需：
#   imports = [ ../../modules/nixos/network ];   # 引入本模块
#   my.easytier.enable = true;                   # 开启；node 默认取 networking.hostName
#   my.easytier.node = "vostro-3420";            # 仅当网格显示名与 hostName 不一致时才写
#
# ───────────────────────────────────────────────────────────────────────────
# 【Nix 语法速查】下面代码用到的写法，先说清楚：
#
# ⒈ `{ config, lib, ... }:` —— 这是「一个 Nix 模块」，本质是一个函数。
#    花括号里的 config / lib 是模块系统“喂”进来的参数：
#      · config —— 整个系统配置的只读视图（读别人的设置用）
#      · lib    —— 标准库（一堆工具函数）
#    末尾的 `...` 意思是“还可能有其他参数，我不关心，别报错”。
#    冒号后面那个 `{ ... }` 才是本模块要“合并进系统”的内容。
#
# ⒉ `let ... in <表达式>` —— 定义一批只在本文件下方可用的局部变量
#    （类似其他语言的局部常量 / let 绑定）。
#
# ⒊ `import ./easytier-nodes.nix` —— 把那个文件求值出来。那个文件是纯数据，
#    求值结果就是一个「属性集」（可以当字典/JSON 对象理解）。
#
# ⒋ `topo.network` —— 访问属性集里的字段（键）。
#    `topo.nodes.${node}` —— 字段名由变量 node 决定，叫「动态取键」。
#    `topo.nodes.${node} or null` —— 如果这个键不存在，就返回 null（不报错）。
#
# ⒌ `f x` —— 函数调用。注意 Nix 里函数和参数用「空格」隔开，没有括号。
#    `(n: 表达式)` —— 匿名函数（lambda），参数名叫 n。
#    `map f 列表` —— 对列表每个元素调用 f，返回新列表。
#    `filter 判定 列表` —— 留下判定为真的元素。
#    `attrNames 属性集` —— 取出所有键，返回字符串列表。
#    `concatMap f 列表` —— 对每个元素调用 f（f 返回列表），再把结果拍平成一个列表。
#
# ⒍ `"${表达式}"` —— 字符串插值，把表达式结果拼进字符串。
#    `"\${...}"`  —— 前面加反斜杠＝转义，写出「字面量 ${...}」，不让 Nix 去插值。
#
# ⒎ `options.xxx = {...}` —— 声明（自定义）一批选项；
#    `config = ...`         —— 真正往系统里写设置；
#    `lib.mkIf 条件 {…}`    —— 只有条件为真时，里面的设置才生效（否则整块消失）。
# ═══════════════════════════════════════════════════════════════════════════

{ config, lib, ... }:

let
  # 读入拓扑表（纯数据文件）→ topo 是个属性集，含 network / cidr / anchors / nodes
  topo = import ./easytier-nodes.nix;

  # 本机节点名：读选项 my.easytier.node（各 host 已设好；默认值是 hostName）
  node = config.my.easytier.node;

  # 在 nodes 表里查本机的虚拟 IP 末段（例如 2）；查不到就是 null（下面断言会明确报错）
  ipSuffix = topo.nodes.${node} or null;

  # 网段 "10.144.144.0/24" 砍掉尾巴 ".0/24" → "10.144.144"（用来拼本机 ipv4）
  prefix = lib.removeSuffix ".0/24" topo.cidr;

  # 组装 peers（初始连接节点）：
  #   attrNames topo.anchors → ["aliyun" "lightsail"]（所有锚点的名字）
  #   filter (n: n != node)  → 把自己剔掉（锚点之间也会互相连）
  #   concatMap (n: ...)     → 把每个锚点对应的 URL 列表拍平成一个大列表
  peers = lib.concatMap (n: topo.anchors.${n}) (
    builtins.filter (n: n != node) (builtins.attrNames topo.anchors)
  );
in
{
  # ── 声明本模块的选项，统一挂在 my.easytier 命名空间下 ──
  options.my.easytier = {
    # mkEnableOption 生成一个布尔选项（默认 false）。别处写 my.easytier.enable = true; 来开
    enable = lib.mkEnableOption "EasyTier 组网（拓扑见 modules/nixos/network/easytier-nodes.nix）";

    # 字符串选项；不写时默认为系统主机名
    node = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "本机在 easytier-nodes.nix 里的节点名，同时用作网格显示名。";
    };
  };

  # ── 真正写进系统的配置：只有 enable = true 时才生效（mkIf 包住整块）──
  config = lib.mkIf config.my.easytier.enable {
    # 断言：本机必须在拓扑表 nodes 里登记过；否则构建直接失败并给出中文提示
    assertions = [
      {
        assertion = ipSuffix != null;
        message = "EasyTier: 节点 \"${node}\" 未在 modules/nixos/network/easytier-nodes.nix 的 nodes 里登记虚拟 IP。";
      }
    ];

    services.easytier = {
      enable = true;

      # main 是这个“实例”的名字（一台机器可以跑多个实例，这里固定用 main）
      instances.main = {
        # 环境文件：从 sops 渲染出的文件里取 ET_NETWORK_SECRET（明文不进 Nix store）
        environmentFiles = [ config.sops.templates."easytier-env".path ];

        settings = {
          instance_name = topo.network;
          hostname = node;
          network_name = topo.network;

          # 关键：这里的 \${...} 是「转义」——写进配置文件的是字面量 ${ET_NETWORK_SECRET}，
          # 等 easytier-core 运行时再自己展开成环境变量里的真口令（所以明文不落 store）
          network_secret = "\${ET_NETWORK_SECRET}";

          # 拼出本机虚拟地址，例如 "10.144.144.2/24"
          ipv4 = "${prefix}.${toString ipSuffix}/24";

          # listeners 用模块默认（tcp+udp 监听 0.0.0.0:11010），这里不写
          peers = peers;
        };

        # flags：EasyTier 的开关集合
        extraSettings.flags = {
          accept_dns = true;   # 魔法 DNS：可用 <hostname>.et.net 互访
          private_mode = true; # 只允许同网络名+口令的节点经本机握手/中转
        };
      };
    };

    # 放行入站 11010（P2P 直连要用）；能否真被外面连上还取决于路由器/云安全组
    networking.firewall.allowedTCPPorts = [ 11010 ];
    networking.firewall.allowedUDPPorts = [ 11010 ];
  };
}
