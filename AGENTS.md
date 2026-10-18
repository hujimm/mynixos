# AGENTS.md — mynixos

Orion 的 NixOS flake，有四个配置输出：`nixosConfigurations.mynixos`（本机 vostro-3420 桌面）、
`nixosConfigurations.aliyun`（阿里云 ECS，nixos-anywhere 安装）、
`nixosConfigurations.lightsail`（AWS Lightsail，nixos-infect 就地安装）与
`nixosConfigurations.lightclaw`（另一台 AWS Lightsail t3.medium，同样 nixos-infect 就地安装）。
硬件目录分别是 `hosts/vostro-3420/`、`hosts/aliyun/`、`hosts/lightsail/`、`hosts/lightclaw/`。

## 硬性规则

- OpenCode 不得手动运行 Nix 求值、格式化或构建验证：包括 `nix eval`、`nix-instantiate`、
  `nix repl`、`nix build` 和 `nixos-rebuild`。最终切换由用户执行。
- 用户明确授权排查其自行触发的构建时，允许只读运行 `nix log <drv>` 查看已有 derivation 日志；
  不得借此启动新的求值、构建或系统切换。
- 必要可用新版 `nix` 命令（如 `nix shell`/`nix run`）临时下载并使用工具/包，
  除上一条允许的 `nix log` 外，不得用它们对本仓库做求值、诊断或构建验证；
  临时环境用完即弃，不写进配置。
- 访问 GitHub 一律用 `gh` 或 `git`（已配置认证，额度 5000 次/小时），**禁止用裸 `curl`**
  请求 GitHub API/raw 内容（未认证限 60 次/小时，会迅速触发限流）；需要看上游仓库的
  README/源码/发布信息时用 `gh repo view`、`gh api` 或浅克隆（`--depth 1 --sparse`）。
- `nixd` 诊断和 `nixfmt` 格式化由 Zed 自动处理；OpenCode 和用户都不要手动调用它们。
  Zed 的 LSP 补全源/格式化/suppress 集中在 `modules/hm/common/nixd.nix`（当前仅
  `zed-editor.nix` 引用，opencode2 已不接 nixd），改这一处即可。

## 配置入口

- 入口链是 `flake.nix` → `hosts/vostro-3420/default.nix` → NixOS 模块与
  `home/orion/default.nix` → Home Manager 模块。
- `hosts/aliyun/` 是云主机 host（`nixosConfigurations.aliyun`）：import 自己的
  `hardware-configuration.nix`、`disk-config.nix`、disko 模块，以及跨主机共用的
  `modules/nixos/server`（云主机基础）与 `modules/nixos/network`（EasyTier），
  **不复用桌面模块**；它是 nixos-anywhere 装出来的，改配置后用
  `nixos-rebuild switch --flake .#aliyun --target-host aliyun-ecs`（用户执行）。
- `hosts/lightsail/` 是 AWS Lightsail host（`nixosConfigurations.lightsail`）。它**不走
  nixos-anywhere/disko**：Lightsail 是 Nitro 平台，kexec 后 ENA/NVMe 不初始化
  （nixos-anywhere issue #139），且不支持导入镜像；故当时用 `nixos-infect` 的 lustrate
  就地安装。**装机用的单文件配置在单独仓库维护，不在本仓库**；本仓库的
  `hosts/lightsail/hardware.nix` 只描述日常硬件（显式 UEFI、ESP 在 `/boot/efi`、
  按 UUID 挂盘），和普通 host 一样参与 rebuild。重建用
  `nixos-rebuild switch --flake .#lightsail --target-host lightsail`（用户执行）。
  **坑（留给装机仓库）**：nixos-infect 就地安装时，必须放开
  `boot.initrd.systemd.enable = false;`。原因：NixOS 26.05 起该选项默认为 true，而
  `NIXOS_LUSTRATE`（首次启动把旧 Ubuntu 整体挪到 `/old-root`）只在 bash 版 stage-1 的
  `lustrateRoot` 里实现，systemd-initrd 没有这段逻辑；首次启动不关就会单元泄漏、
  网络起不来 → 装完失联（Lightsail 与 EC2 一致，已在 EC2 串口实锤）。lustrate 只发生
  一次（新根上已无 `/etc/NIXOS_LUSTRATE`，清单在 `/old-root/`），已装好的机器日常
  重建用默认 systemd-initrd 即可，也免掉 26.11 移除脚本式 initrd 的警告。
- `hosts/lightclaw/` 是第二台 AWS Lightsail（`nixosConfigurations.lightclaw`，t3.medium、悉尼、
  80G 盘），同样用 nixos-infect 就地安装。与 lightsail 出自**同一 AMI，三个分区的
  UUID/PARTUUID 完全相同**（装机清理 `/old-root` 后已无 Ubuntu 残留）。
  它跑**一个 OpenClaw 网关**（`programs.openclaw`，Home Manager 用户服务，见
  `hosts/lightclaw/openclaw.nix`）。为此本机引入了 Home Manager（flake 里加
  `home-manager.nixosModules.home-manager`，`useGlobalPkgs`），新增专用用户 `openclaw`
  （`linger` + 免密 `sudo`），密钥走 sops（`hosts/lightclaw/sops.nix`；本机**不在 EasyTier
  网格**，故不 import `sops-cloud.nix`，避免连带引入网络口令）。`nixpkgs.overlays` 加入
  `nix-openclaw`。**仍未加入 EasyTier 网格**。重建用
  `nixos-rebuild switch --flake .#lightclaw --target-host lightclaw`（用户执行），
  或在服务器上 `nixos-rebuild switch --flake github:hujimm/mynixos#lightclaw`；
  其装机单文件配置（hostName=lightclaw、2GiB swap+zswap、关闭 systemd-initrd）与 lightsail
  一样不在本仓库。
- `--target-host` 是“本机构建、拷贝到远端”，**GC root 建在远端**，本机这份闭包无根，
  会被本机 nightly `nix.gc`（`--delete-older-than 3d`）回收，导致每次重建 aliyun 又把
  只属于它的包重编。做法：在本机保留一个 root：
  `nix build .#nixosConfigurations.aliyun.config.system.build.toplevel -o ~/nixos-aliyun`。
  替代方案是 `--build-host aliyun-ecs`（在服务器构建、复用服务器 store，但受云主机内存限制）。
- 各模块目录通过 `default.nix` 聚合导入；新增模块必须挂到对应聚合器，不能绕过 module system。
- `modules/nixos/network/` 是跨主机共用的 EasyTier 组网模块（独立于 `programs/`/`services/`，
  桌面与各云主机 host 都能 import）。**网络拓扑是唯一事实来源**：网络名、网段、锚点、
  每个节点的虚拟 IP 全在 `easytier-nodes.nix` 一个文件里（锚点的值是多地址列表，可同时写 v4/v6）；每台 host 只需
  `imports = [ ../../modules/nixos/network ];` 加 `my.easytier.enable = true;`，
  网格显示名与 `networking.hostName` 不一致时（如桌面 hostName 是 `mynixos`）再写
  `my.easytier.node = "vostro-3420";`。加机器 = 拓扑表加一行 + 该机两行。
  EasyTier 口令的 sops 声明与 `easytier-env` 模板抽在
  `modules/nixos/security/easytier-secret.nix`，凡加入网络的 host 让其 sops 配置 import 它
  （云主机经 `sops-cloud.nix` 自动 import；各机 age 公钥仍列在 `.sops.yaml`）；新增能解密口令的主机需同步
  `modules/nixos/security/.sops.yaml` 的 `secrets/easytier.yaml` 规则并 `sops updatekeys`。
- `modules/nixos/server/` 是云主机（aliyun / lightsail）共用的基础模块：UEFI GRUB
  （可移动回退路径，ESP 挂载点由各 host 设）、2GiB swapfile + zswap、SSH 加固、DHCP、
  时区、git/vim、nix 设置与 GC。**桌面不 import**；host 特有内容（磁盘、内核模块、
  SSH 公钥、专有服务）留在 `hosts/`。两台云主机的 sops 骨架抽在
  `modules/nixos/security/sops-cloud.nix`，各自的 `sops.nix` 只写 `defaultSopsFile`
  与自己的密钥。
- `modules/_trash/` 是废弃配置垃圾桶：不会被任何 default.nix 导入，扔进去的文件等系统切换
  确认无误后再删；不要从里面 import 任何东西。
- `modules/hm/common/` 是被模块直接 `import` 的共享数据，不是模块目录。

## 不可随意破坏的约定

- 不要修改 `modules/hm/ai-agent/opencode2.nix`；当前会话依赖它的 OpenCode 安装
  （opencode2 是 OpenCode v2 的程序名，不是迁移命名）。
- `modules/hm/desktop/niri-config/` 由 `modules/hm/desktop/niri.nix` 递归挂载到
  `~/.config/niri`，包括 `test/`；改 Niri 直接改 `.kdl`，不要在 Nix 中重写。
- 微信/WPS 在 `modules/hm/programs/packages.nix` 中通过 `symlinkJoin` + `wrapProgram` 包装以接入 fcitx；
  升级时只换包名，不要破坏包装参数。
- `wallpaper/` 是运行时路径：Noctalia 直接读 `~/mynixos/wallpaper`（`modules/hm/desktop/noctalia.nix`，
  不是 store 路径），加/删壁纸只是放文件进目录，不需要 rebuild。该目录已被 `.gitignore` 忽略，
  不入仓库，新增壁纸直接放文件即可。
- Niri 内屏当前 scale 是 `1.5`；fcitx5 的 XWayland 候选框依赖 `Xft.dpi = 144`。修改
  `outputs.kdl` 的 scale 时，必须同步检查 `fcitx5-rime-ice.nix` 与 `miscellaneous.kdl`。
- fish 别名在 `modules/hm/programs/shell.nix`，目前只有 `ll`/`la`/`...`；文档旧版提到的
  `f`/`uf` 代理开关在当前仓库中并不存在，CLI 走代理需手动导出 `https_proxy`/`http_proxy`。
- system/home 的 `stateVersion` 都是 `"26.05"`，未明确理解迁移影响前不要修改。
- `hosts/vostro-3420/hardware-configuration.nix` 由安装器生成，挂载 Btrfs 多子卷
  （`@`、`@home`、`@nix`、`@snapshots`、`@swap`）与 vfat ESP；修改前先备份。
- Home Manager 的 `backupFileExtension = "hm-backup"`（`hosts/vostro-3420/default.nix`）：
  手动改动 HM 托管的 `~/.config` 文件后，下次 rebuild 原文件会被改名为 `*.hm-backup` 并被覆盖，不要依赖手动改动。
- Hermes 的 NixOS 服务（`services.hermes-agent`）已废弃：配置在
  `modules/_trash/nixos/hermes-agent.nix`（未被导入，确认后删除）。
- Hermes 的 HM 用户级入口 `modules/hm/ai-agent/hermes.nix`：从 `hermes-agent`
  （Tier 2 无 CI 的 flake，保持独立 nixpkgs pin）取包安装，密钥放 `~/.hermes/.env`，
  升级前先查上游提交再 `nix flake lock --update-input hermes-agent`。
- `modules/hm/ai-agent/` 只有 OpenCode（opencode2）、Hermes CLI 与 dsh（deepseek-harness，配合
  hosts 的 overlay 注入 `pkgs.dsh`）的安装配置；
  Hermes 的 NixOS 服务已废弃（见上），不再有 `modules/nixos/ai-agent/`。
- 注释使用中文；避免为单机配置引入不必要的抽象。

## Inputs 与操作

- 根 `nixpkgs` 是 `nixos-unstable`；Home Manager、Zen beta 和 Spicetify 跟随根 nixpkgs。
  Noctalia 和 fcitx5-vinput 保持独立的 nixpkgs，AyuGram 使用带 submodules 的 Git input，不要擅自改这些关系。
- 涉及 nixpkgs 包名、上游模块选项或版本时，**优先用 `nixos` MCP 查询**（见"Nix 查询（mcp-nixos
  远程 MCP）"一节），不要凭旧记忆猜测；MCP 查不到再退回 websearch。
- 用户执行系统切换：`sudo nixos-rebuild switch --flake .#mynixos`。
- 用户更新输入：`nix flake update` 或 `nix flake lock --update-input <name>`。

## Nix 查询（mcp-nixos 远程 MCP）

- 涉及 nixpkgs 包名、NixOS / Home Manager / nix-darwin / nixvim / NVF 选项、flake、二进制缓存
  或版本历史时，**优先直接用 `nixos` MCP 工具查询**：`tools.nixos.nix(...)`（search/info/stats/
  browse/channels/cache 等）与 `tools.nixos.nix_versions(...)`；结果实时、比旧记忆或 websearch 准。
  查不到或工具不可用时再退回 websearch。
- 它是**远程 MCP**：server 常驻在阿里云 ECS，客户端经 EasyTier 覆盖网访问。本机 OpenCode 配置是
  用户级文件 `~/.config/opencode/opencode.json`（`type: "remote"`、
  `url: "http://10.144.144.1:8000/mcp"`、`oauth: false`，**不入仓库**），改动后需重启 OpenCode 生效。
- 服务端在 `hosts/aliyun/mcp-nixos.nix`：`mcp-nixos` 以 HTTP transport（stateless）跑成 systemd
  `mcp-nixos.service`，只绑 EasyTier 网卡 `10.144.144.1:8000`，防火墙仅对 `tun0` 放行。
  该 server **无内置鉴权**，且 `store`/`flake-inputs` 动作能读所在机器的 `/nix/store`，
  所以**绝不能把 `MCP_NIXOS_HOST` 改成 `0.0.0.0`**，也不要对公网开放端口。
- 使用前提：设备需先连上 EasyTier 网络（`ctmiop`）才能访问。改完 `hosts/aliyun/` 后由用户执行
  `nixos-rebuild switch --flake .#aliyun --target-host aliyun-ecs`（见"配置入口"的 GC root 提醒）。
- 已知限制：服务器上 `api.github.com` 被限速，`channels` 这类动作可能超时；其余查询正常。

## 代理软件（两套，互相独立）

本机有**两个独立代理程序、两个不同机场**，端口、数据目录、TUN 设备名都不同，排查前先分清是哪一套，
不要互相套用：

- **闪狐 FlashFox Lite**（`flashfox-lite`，仓库入口 `modules/nixos/programs/flashfox-lite.nix`）：
  混合端口 **7892**；TUN 设备名固定 **`Meta`**（`stack: mixed`、`auto-route: false`）；
  数据在 `~/.local/share/com.ffclient.app/`；订阅走自己账号（ppanel API，名称在 prefs 里加密）。
- **Clash Verge Rev**（`clash-verge-rev`，GUI 自管、**不在仓库**）：混合端口 **7897**；
  TUN 设备名 **`Mihomo`**（`stack: gvisor`、`auto-route: true`）；
  数据在 `~/.local/share/io.github.clash-verge-rev.clash-verge-rev/`；订阅是"赔钱机场"（`dasho.pqjc.site`）。

要点：

- 闪狐的系统代理是 **7892**，与 Clash 的 7897 无关；闪狐不开时 7892 不监听属正常。
  注意 7892 是"系统代理"，只对浏览器/GUI 生效，`gh`/`curl`/`git` 不读取它，需手动
  `export https_proxy=http://127.0.0.1:7892`。
- 两个 TUN **不要同时开**：闪狐 `auto-route: false`、Clash `auto-route: true`，会争抢全局路由。
- **设备名撞车坑**：mihomo 内核默认 TUN 设备名就是 `Meta`；Clash Verge 的 TUN 设置对话框里
  "虚拟网卡名称"默认显示 `Mihomo` 但**只有点"保存"才会写进 `config.yaml` 的 `tun.device`**，
  没保存时 mihomo 回退到内置默认 `Meta`，与闪狐撞名（详见下节 flashfox-tun-cleanup）。
  排查 Clash TUN 时先看 `grep device ~/.local/share/io.github.clash-verge-rev.clash-verge-rev/config.yaml`。

## 闪狐（flashfox-lite）

- 来源：独立 flake `github:hujimm/flashfox-lite-flake`（系统代理与 TUN 均已完整适配
  NixOS 且**可同时开启**，机制细节见其 README 与 TUN-RESEARCH.md（§15 3.0.6、§17 3.2.1 复盘）；
  输入跟随根 nixpkgs）。当前版本 3.2.1（2026-09 升级，含 /opt bundle 迁移、librust_api、
  libsecret、schema 目录、数据目录迁移五个适配点）。
- 本仓库入口：`modules/nixos/programs/flashfox-lite.nix`（`enable = true; enableTun = true;`）。
  升级/换版本流程：flashfox-lite-flake 上游先发布新 commit（按其 AGENTS.md 升级流程），
  再改 flake 输入，由用户执行 `nix flake lock --update-input flashfox-lite` + rebuild。
- 运行时数据在 `~/.local/share/com.ffclient.app/`（**3.2.1 起从 `ffclient.app` 迁移，
  别写错目录**——曾致设备名修正失效、TUN 残留、系统代理 7892 国外全挂），由 GUI 管理
  （会整体重写），**不要手动编辑** `shared_preferences.json`——尤其 `patchClashConfig.tun.device`
  （包内包装器在 GUI 每次启动前自动幂等修正为 `Meta`，与防火墙 trustedInterfaces 约定一致）
  和 `log-level`。
- TUN 的提权与免密由上游 flake 模块自动完成（setuid wrapper + bind-mount + 假 sudo）：
  不要手动 chmod/chown core 文件，也不要停用 `flashfox-core-mount.service`。
- 上游模块还装了 `flashfox-tun-cleanup.timer`（每 15s 触发同名 service，清理闪狐残留的
  `Meta` 接口 / 9000-9010 ip rule / table 2022；脚本第一行 `ip link show Meta || exit 0`，
  即只认 `Meta` 这一个名字）。**它无法区分 `Meta` 属于闪狐还是别的 mihomo 内核**：
  闪狐没跑时任何叫 `Meta` 的接口都会被它当残留删掉（曾把 Clash Verge 的 TUN 删掉，
  Clash 侧表现为"开关是开的但 `ip link` 没有接口、直连国外全挂"）。
  所以 Clash 侧必须把 TUN 设备名保存成 `Mihomo`（见"代理软件"节），别让两边都用 `Meta`。
- 验证要点：开 TUN 不弹密码框、google/baidu 直连正常；`ip addr show Meta`；
  `stat -c '%U:%G %A' "$(readlink -f /run/current-system/sw/bin/flashfox-lite | xargs dirname | xargs dirname)/share/FlashFoxLite/FlashFoxLiteCore"`
  应为 `root:root -rws--x--x`（老命令的 `/run/current-system/sw/share/...` 路径 3.2.1 已不存在）；
  系统代理（127.0.0.1:7892）与 TUN 可同时使用、互不干扰；7892 走国外全挂时先查残留
  `Meta` 接口/2022 路由表/9000-9010 ip rule（GUI 关 TUN 后 Core 残留会留着它们，
  清理：`sudo ip link del Meta` + `sudo ip rule del pref 900x` + `sudo ip route flush table 2022`）。

## MATLAB（R2020b，本地 FHS 包装）

- 入口：`modules/nixos/programs/matlab.nix`（已在 `programs/default.nix` 聚合导入）。
  MATLAB **不在 nixpkgs**，也不走 flake input——故意不挂 `nix-matlab`（上游已归档，且其
  nixpkgs pin 会漂移）。用 `buildFHSEnv` 做启动器，本体由官方安装器命令式装在用户目录。
- 安装形态：本体在 `~/MATLAB/R2020b`（官网 installer 初始化为用户目录、学校账号在线激活），
  许可在 `~/.matlab/R2020b_licenses/`；`~/.config/matlab/nix.sh` 写
  `INSTALL_DIR=$HOME/MATLAB/R2020b`（Nix/HM 都不托管，不会被 `*.hm-backup` 覆盖）。
- 两个入口：`matlab-shell` 进 FHS 跑官网 `./install` 用；`matlab`/`matlab -desktop` 是日常启动。
- 启动器已固化：`QT_QPA_PLATFORM=xcb` + `LD_PRELOAD=/lib/libstdc++.so` + `-softwareopengl`，
  并后台 `wmname LG3D`。这些是修 Niri/Wayland 下**窗口空白**的，别当多余删掉。
- 依赖清单按当前 nixos-unstable 修正过的点：用 `buildFHSEnv`（不是已删的 `buildFHSUserEnv`）；
  `pkgs.xorg.*` 全换顶层小写新名（`libx11`、`libsm`…，xorg 包集已废弃）；`mesa` 不用 `mesa.drivers`；
  `gtk2` 条件引入（存在才加）；显式加 `freetype` 盖掉 MATLAB 捆绑的旧版（否则 harfbuzz 报
  `FT_Get_Color_Glyph_Layer` 未定义）。
- 坑：安装器窗口不出来 → 把安装包 `bin/glnxa64`、`sys/os/glnxa64` 下的
  `libstdc++.so.6*`/`libfreetype.so.6*` 改名 `.distlink` 再跑；装完后 GUI 空白同法处理。
- 已知无效设置：`s.matlab.desktop.DisplayScaleFactor` 设小数（如 1.5）无效——R2020b 用 Java 8，
  Linux 下只支持整数缩放。R2020b 在 Niri 内屏 `scale 1.5` 下界面发糊是 **XWayland 非整数缩放的
  固有限制**：XWayland 给 MATLAB 逻辑 1280×720，Niri 再放大到 1080p。`Xft.dpi=144`
  （`fcitx5-rime-ice.nix` 经 `xrdb` 注入）只影响字体，不改 `ScreenPixelsPerInch`。
  根治要么把 `outputs.kdl` 的 scale 改 1，要么升 R2025a+（新版 WebGL/新 Java 对小数缩放更好）；
  当前已接受现状，升级/改 scale 前先确认。
