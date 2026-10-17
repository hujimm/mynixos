# ═══════════════════════════════════════════════════════════════════════════
# EasyTier 网络口令的 sops 声明（桌面 / aliyun / lightsail 共用）
# ═══════════════════════════════════════════════════════════════════════════
# 口令文件本身是加密的（./secrets/easytier.yaml），明文不会进 Nix store。
# 各机器要解密它，靠的是各自不同的 age 私钥——那部分仍写在各 host 自己的 sops.nix
# （桌面用 keyFile，云主机用 SSH host key 派生）。所以凡是加入 EasyTier 的 host，
# 只要让它 sops 配置 `import` 本文件，就不必再各自抄一遍 secret / template。
#
# 【语法】
#  · `{ config, ... }:` 模块函数，只用到 config（读别的设置），`...` 表示其余参数忽略。
#  · `sops.secrets."名字" = { ... };` —— 声明“有一个密钥文件叫这个名字”。
#  · `sops.templates."名字" = { ... };` —— 声明“渲染出一个文件”，内容里可以引用密钥。
#  · `./secrets/easytier.yaml` —— 相对本文件所在目录的路径。
#  · `${config.sops.placeholder."xxx"}` —— 字符串插值：sops 会在合适的时机把这里
#    替换成“指向解密后内容”的路径占位符，最终生成的文件里就是真值（明文只落在运行时）。
# ═══════════════════════════════════════════════════════════════════════════
{ config, ... }:

{
  # 密钥：明文值放在加密文件 ./secrets/easytier.yaml 的 easytier-network-secret 字段里
  sops.secrets."easytier-network-secret".sopsFile = ./secrets/easytier.yaml;

  # 模板：把上面那条密钥渲染成一个 systemd EnvironmentFile（环境变量文件）。
  # 供 easytier-core 读取配置时展开 ${ET_NETWORK_SECRET}（见 modules/nixos/network/easytier.nix）。
  # mode 0400 = 只有属主可读写，别人看不到口令。
  sops.templates."easytier-env" = {
    content = "ET_NETWORK_SECRET=${config.sops.placeholder."easytier-network-secret"}";
    mode = "0400";
  };
}
