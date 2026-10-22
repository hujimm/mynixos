# mynixos

Orion 的单机 NixOS 配置，Flake 仓库。

## 结构

- `flake.nix` — 入口，含 inputs 与缓存/信任密钥配置
- `hosts/vostro-3420/` — 本机硬件与主机级配置
- `modules/nixos/` — 系统模块
- `modules/hm/` — Home Manager 模块
- `modules/_trash/` — 废弃配置垃圾桶
- `wallpaper/` — 运行时壁纸目录（不入 store）


## 个人说明

### 未被声明的部分

1. wanxiang-lts-zh-hans ，万象语法模型（ https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram ） 需手动下载放在 ~/.local/share/fcitx5/rime/ 下。
2. 浏览器 账户 cookie 相关数据: zen-browser google-chrome 
3. ai 相关：hermes opencode2
4. 机场账户 
5. sops-nix 私钥放在/var/lib/sops-nix/key.txt
6. fcitx5-vinput 的设置:豆包输入法
7. wallpaper 放在./ 下
