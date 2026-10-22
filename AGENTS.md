# AGENTS.md — mynixos

Orion 的 NixOS flake，有三个配置输出：`nixosConfigurations.mynixos`（本机 vostro-3420 桌面）、
`nixosConfigurations.aliyun`（阿里云 ECS，nixos-anywhere 安装）、
`nixosConfigurations.lightsail`（AWS Lightsail，nixos-infect 就地安装）。
硬件目录分别是 `hosts/vostro-3420/`、`hosts/aliyun/`、`hosts/lightsail/`。

## 硬性规则

- OpenCode 不得对本仓库运行求值、格式化或构建验证：`nix eval`、`nix-instantiate`、
  `nix repl`、`nix build`、`nixos-rebuild` 都不行，系统切换由用户执行。用户明确授权排查其自行
  触发的构建时，可只读运行 `nix log <drv>` 查看已有 derivation 日志，不得借此启动新的求值、
  构建或切换。
- 临时工具用 `nix shell`/`nix run`：同样不得借它们对本仓库求值、诊断或构建验证；用完即弃，
  不写进配置。
- 访问 GitHub 一律用 `gh` 或 `git`（已配置认证，额度 5000 次/小时），**禁止用裸 `curl`**
  请求 GitHub API/raw 内容（未认证限 60 次/小时，会迅速触发限流）；看上游仓库的
  README/源码/发布信息用 `gh repo view`、`gh api` 或浅克隆（`--depth 1 --sparse`）。
- `nixd` 诊断和 `nixfmt` 格式化由 Zed 自动处理，不要手动调用；两者的配置在
  `modules/hm/common/nixd.nix`，改这一处即可。
- **`modules/_trash/` 是只读的配置片段库**：放以前用过、以后可能再抄的配置。单文件放
  `nixos/`、`hm/`，横跨两者的多文件项目放 `projects/<名字>/`。进这里的东西只保留配置本身和
  「换台机器还会再踩的坑」，不写归档日志、恢复步骤、README、密钥接线。要再删或再改先问用户。

## 配置入口

- 入口链是 `flake.nix` → `hosts/vostro-3420/default.nix` → NixOS 模块与
  `home/orion/default.nix` → Home Manager 模块。
- `hosts/aliyun/` 是云主机 host：import 自己的 `hardware-configuration.nix`、
  `disk-config.nix`、disko 模块，以及跨主机共用的 `modules/nixos/server`（云主机基础）与
  `modules/nixos/network`（EasyTier），**不复用桌面模块**。改配置后用
  `nixos-rebuild switch --flake .#aliyun --target-host aliyun-ecs`（用户执行）。
- `hosts/lightsail/` **不走 nixos-anywhere/disko**：Lightsail 是 Nitro 平台，kexec 后
  ENA/NVMe 不初始化（nixos-anywhere issue #139），也不支持导入镜像。装机用的单文件配置在
  单独仓库维护，不在本仓库；本仓库的 `hosts/lightsail/hardware.nix` 只描述日常硬件
  （显式 UEFI、ESP 在 `/boot/efi`、按 UUID 挂盘），和普通 host 一样参与 rebuild。重建用
  `nixos-rebuild switch --flake .#lightsail --target-host lightsail`（用户执行）。
- 装机仓库的坑：NixOS 26.05 起 `boot.initrd.systemd.enable` 默认为 true，而 `NIXOS_LUSTRATE`
  （首次启动把旧系统整体挪到 `/old-root`）只在 bash 版 stage-1 的 `lustrateRoot` 里实现，
  systemd-initrd 没有这段逻辑；nixos-infect 装机时首次启动不关它就会单元泄漏、网络起不来，
  装完失联。lustrate 只发生一次，装好后日常重建用默认的 systemd-initrd 即可。
- `--target-host` 是「本机构建、拷贝到远端」，**GC root 建在远端**，本机这份闭包无根，
  会被本机 nightly `nix.gc`（`--delete-older-than 3d`）回收，于是每次重建 aliyun 都要重编
  只属于它的包。做法是在本机保留一个 root：
  `nix build .#nixosConfigurations.aliyun.config.system.build.toplevel -o ~/nixos-aliyun`。
  替代方案是 `--build-host aliyun-ecs`（在服务器构建、复用服务器 store，但受云主机内存限制）。
- 各模块目录通过 `default.nix` 聚合导入；新增模块必须挂到对应聚合器，不能绕过 module system。
- `modules/nixos/network/` 是跨主机共用的 EasyTier 组网模块（独立于 `programs/`/`services/`，
  桌面与各云主机 host 都能 import）。**网络拓扑是唯一事实来源**：网络名、网段、锚点、
  每个节点的虚拟 IP 全在 `easytier-nodes.nix` 一个文件里（锚点的值是多地址列表，可同时写
  v4/v6）。每台 host 只需 `imports = [ ../../modules/nixos/network ];` 加
  `my.easytier.enable = true;`；网格显示名与 `networking.hostName` 不一致时（如桌面
  hostName 是 `mynixos`）再写 `my.easytier.node = "vostro-3420";`。加机器 = 拓扑表加一行 +
  该机两行。EasyTier 口令的 sops 声明与 `easytier-env` 模板在
  `modules/nixos/security/easytier-secret.nix`，桌面经 `security/default.nix`、云主机经
  `sops-cloud.nix` 自动导入；新增能解密口令的主机需同步
  `modules/nixos/security/.sops.yaml` 的 `secrets/easytier.yaml` 规则并 `sops updatekeys`。
- `modules/nixos/server/` 是云主机（aliyun / lightsail）共用的基础模块：UEFI GRUB
  （可移动回退路径，ESP 挂载点由各 host 设）、2GiB swapfile + zswap、SSH 加固、DHCP、
  时区、git/vim、nix 设置与 GC。**桌面不 import**；host 特有内容（磁盘、内核模块、
  SSH 公钥、专有服务）留在 `hosts/`。两台云主机的 sops 骨架在
  `modules/nixos/security/sops-cloud.nix`，各自的 `sops.nix` 只写 `defaultSopsFile`
  与自己的密钥。
- `modules/_trash/` 不会被任何 `default.nix` 导入，也不要从里面 import 任何东西。
- `modules/hm/common/` 是被模块直接 `import` 的共享数据，不是模块目录。

## 不可随意破坏的约定

- `modules/hm/desktop/niri-config/` 由 `modules/hm/desktop/niri.nix` 递归挂载到
  `~/.config/niri`（含 `test/`）；改 Niri 直接改 `.kdl`，不要在 Nix 中重写。
- 微信/WPS 在 `modules/hm/programs/packages.nix` 中通过 `symlinkJoin` + `wrapProgram` 包装以
  接入 fcitx；升级时只换包名，不要破坏包装参数。
- `wallpaper/` 是运行时路径：Noctalia 直接读 `~/mynixos/wallpaper`
  （`modules/hm/desktop/noctalia.nix`，不是 store 路径），加/删壁纸只是往目录放文件，
  不需要 rebuild；该目录已被 `.gitignore` 忽略，不入仓库。
- Niri 内屏 scale 是 `1.5`；fcitx5 的 XWayland 候选框依赖 `Xft.dpi = 144`。修改
  `outputs.kdl` 的 scale 时必须同步检查 `fcitx5-rime-ice.nix` 与 `miscellaneous.kdl`。
- system/home 的 `stateVersion` 都是 `"26.05"`，未明确理解迁移影响前不要修改。
- `hosts/vostro-3420/hardware-configuration.nix` 由安装器生成，挂载 Btrfs 多子卷
  （`@`、`@home`、`@nix`、`@snapshots`、`@swap`）与 vfat ESP；修改前先备份。
- Home Manager 的 `backupFileExtension = "hm-backup"`（`hosts/vostro-3420/default.nix`）：
  手动改动 HM 托管的 `~/.config` 文件后，下次 rebuild 原文件会被改名为 `*.hm-backup` 并被
  覆盖，不要依赖手动改动。
- Hermes 桌面端在 `modules/hm/ai-agent/hermes.nix`，从 `hermes-agent` flake（无 CI，独立 pin）
  取包安装，密钥放 `~/.hermes/.env`；升级前先查上游提交，再
  `nix flake lock --update-input hermes-agent`。
- `modules/hm/ai-agent/` 只有 OpenCode（opencode2）与 Hermes CLI 的安装配置。
- 注释使用中文；避免为单机配置引入不必要的抽象。

## Inputs 与操作

- 根 `nixpkgs` 是 `nixos-unstable`；Home Manager、Zen beta 和 Spicetify 跟随根 nixpkgs。
  Noctalia 和 fcitx5-vinput 保持独立的 nixpkgs，AyuGram 使用带 submodules 的 Git input，
  不要擅自改这些关系。
- 用户执行系统切换：`sudo nixos-rebuild switch --flake .#mynixos`。
- 用户更新输入：`nix flake update` 或 `nix flake lock --update-input <name>`。

## Nix 查询（mcp-nixos 远程 MCP）

- 涉及 nixpkgs 包名、NixOS / Home Manager / nix-darwin / nixvim / NVF 选项、flake、二进制缓存
  或版本历史时，优先用 `tools.nixos.nix(...)`（search/info/stats/browse/channels/cache 等）与
  `tools.nixos.nix_versions(...)`；结果实时，比旧记忆或 websearch 准。查不到或工具不可用时
  再退回 websearch。
- 它是远程 MCP：server 常驻阿里云 ECS，客户端经 EasyTier 覆盖网访问。本机 OpenCode 配置是
  用户级文件 `~/.config/opencode/opencode.json`（`type: "remote"`、
  `url: "http://10.144.144.1:8000/mcp"`、`oauth: false`，**不入仓库**），改动后需重启 OpenCode。
- 服务端在 `hosts/aliyun/mcp-nixos.nix`：`mcp-nixos` 以 HTTP transport（stateless）跑成 systemd
  `mcp-nixos.service`，只绑 EasyTier 网卡 `10.144.144.1:8000`，防火墙仅对 `tun0` 放行。
  该 server **无内置鉴权**，且 `store`/`flake-inputs` 动作能读所在机器的 `/nix/store`，
  所以**绝不能把 `MCP_NIXOS_HOST` 改成 `0.0.0.0`**，也不要对公网开放端口。
- 使用前提：设备需先连上 EasyTier 网络（`ctmiop`）。改完 `hosts/aliyun/` 后由用户执行
  `nixos-rebuild switch --flake .#aliyun --target-host aliyun-ecs`（见「配置入口」的 GC root
  提醒）。
- 已知限制：服务器上 `api.github.com` 被限速，`channels` 这类动作可能超时；其余查询正常。

## 代理软件（两套，互相独立）

本机有**两个独立代理程序、两个不同机场**，端口、数据目录、TUN 设备名都不同，排查前先分清
是哪一套，不要互相套用：

- **闪狐 FlashFox Lite**（`flashfox-lite`，仓库入口 `modules/nixos/programs/flashfox-lite.nix`）：
  混合端口 **7892**；TUN 设备名固定 **`Meta`**（`stack: mixed`、`auto-route: false`）。
- **Clash Verge Rev**（`clash-verge-rev`，GUI 自管、**不在仓库**）：混合端口 **7897**；
  TUN 设备名 **`Mihomo`**（`stack: gvisor`、`auto-route: true`）；
  数据在 `~/.local/share/io.github.clash-verge-rev.clash-verge-rev/`；订阅是「赔钱机场」
  （`dasho.pqjc.site`）。

要点：

- 7892 是闪狐的「系统代理」，只对浏览器/GUI 生效，`gh`/`curl`/`git` 不读取它，需手动
  `export https_proxy=http://127.0.0.1:7892`；闪狐不开时 7892 不监听属正常。
- 两个 TUN **不要同时开**：闪狐 `auto-route: false`、Clash `auto-route: true`，会争抢全局路由。
- **TUN 设备名**：mihomo 内核默认设备名就是 `Meta`；Clash Verge 的 TUN 设置对话框里
  「虚拟网卡名称」预填 `Mihomo`，但**只有点「保存」才会写进 `config.yaml` 的 `tun.device`**，
  没保存时回退到 `Meta`，会被闪狐的 cleanup timer 当作残留删掉。所以 Clash 侧必须保存成
  `Mihomo`；排查时先看
  `grep device ~/.local/share/io.github.clash-verge-rev.clash-verge-rev/config.yaml`。

## 闪狐（flashfox-lite）

- 来源：独立 flake `github:hujimm/flashfox-lite-flake`（输入跟随根 nixpkgs），系统代理与 TUN
  都适配了 NixOS 且可以同时开启。本仓库入口 `modules/nixos/programs/flashfox-lite.nix`
  （`enable = true; enableTun = true;`）。升级：上游先发布新 commit（按其 AGENTS.md 升级流程），
  再改 flake 输入，由用户执行 `nix flake lock --update-input flashfox-lite` + rebuild。
- 运行时数据在 `~/.local/share/com.ffclient.app/`，由 GUI 管理（会整体重写），**不要手动编辑**
  `shared_preferences.json`——尤其 `patchClashConfig.tun.device`（包内包装器在 GUI 每次启动前
  幂等修正为 `Meta`）和 `log-level`。路径写错会让设备名修正失效、TUN 残留、7892 国外全挂。
- TUN 的提权与免密由上游 flake 模块自动完成（setuid wrapper + bind-mount + 假 sudo）：
  不要手动 chmod/chown core 文件，也不要停用 `flashfox-core-mount.service`。
- 上游模块装有 `flashfox-tun-cleanup.timer`（每 15s 触发同名 service，清理残留的 `Meta` 接口 /
  9000-9010 ip rule / table 2022；脚本第一行 `ip link show Meta || exit 0`，只认 `Meta` 这一个
  名字）。它无法区分 `Meta` 属于闪狐还是别的 mihomo 内核，闪狐没跑时任何叫 `Meta` 的接口
  都会被当作残留删掉。
- 验证要点：开 TUN 不弹密码框、google/baidu 直连正常、`ip addr show Meta`；core 文件权限用
  `stat -c '%U:%G %A' "$(readlink -f /run/current-system/sw/bin/flashfox-lite | xargs dirname | xargs dirname)/share/FlashFoxLite/FlashFoxLiteCore"`
  查，应为 `root:root -rws--x--x`。7892 走国外全挂时先查残留 `Meta` 接口/2022 路由表/9000-9010
  ip rule（GUI 关 TUN 后 Core 残留会留着它们），清理：`sudo ip link del Meta` +
  `sudo ip rule del pref 900x` + `sudo ip route flush table 2022`。
