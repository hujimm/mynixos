# MATLAB R2020b 配置与安装流程（存档）

> 归档日期：2026-10-19。用户已不再使用 MATLAB，原模块
> `modules/nixos/programs/matlab.nix` 原样移到本目录（`matlab.nix`），
> 并从 `modules/nixos/programs/default.nix` 的 imports 中移除。
> 本文件记录当时的打包方式与安装流程，方便以后需要时照着重装/恢复。
>
> 注意：按仓库规则，`modules/_trash/` 只进不出、永不改写。
> 这里的内容不会被任何 `default.nix` 导入，**不要从 `_trash` import**。

## 一、当时的做法：仓库只管启动器，不管安装包

MATLAB 是专有软件，许可禁止再分发，所以没有、也不应该把本体打成 Nix derivation：

- 安装包（R2020b Linux zip）从 MathWorks 官网用学校账号下载，不入仓库、不进 store。
- 本体用官方安装器命令式装到 `~/MATLAB/R2020b`（约 4.1 GB）。
- 许可证文件在 `~/.matlab/R2020b_licenses/license_<hostname>_<SN>_R2020b.lic`，
  按机器 HOSTID 固定，到期后需重新申请。
- `~/.config/matlab/nix.sh` 只有一行 `INSTALL_DIR=$HOME/MATLAB/R2020b`，
  由 Nix/HM 之外的命令式步骤写入（因此不会被 `*.hm-backup` 覆盖）。
- 仓库提供的只是 `pkgs.buildFHSEnv` 生成的两个启动器：
  - `matlab`：日常启动，`exec $INSTALL_DIR/bin/matlab -softwareopengl "$@"`；
  - `matlab-shell`：给官方 `./install` 用的 FHS shell（安装前 `INSTALL_DIR` 不存在也能进）。

依赖清单（`matlabTargetPkgs`）抄自上游 `sceptri/nix-matlab` 的 `common.nix`
（源头是 MathWorks R2020a Dockerfile），并按当时 nixos-unstable 修正过：

- `buildFHSUserEnv` → `buildFHSEnv`；
- 已删除的 `gnome2.gtk` → 按需引入的 `gtk2`（`lib.optional (hasAttr "gtk2")`）；
- 已废弃的 `mesa.drivers` → `mesa`；
- `pkgs.xorg.*` 全换顶层小写新名（`libx11`、`libsm`…）；
- 显式加 `freetype`，盖掉 MATLAB 捆绑的旧版（否则 harfbuzz 报
  `FT_Get_Color_Glyph_Layer` 未定义）。

**故意没有**挂 `nix-matlab` flake input：上游已归档，且其 nixpkgs pin 会漂移，
只会把整个 flake 的 nixpkgs 拖住。缺依赖时抄清单即可。

## 二、当天的安装流程（可复用）

1. 学校账号登录 `mathworks.com/mwaccount` → **Previous releases** →
   R2020b、Linux，下载安装包（zip）。
2. 解压，保留权限位（安装器脚本需要可执行）：
   ```sh
   unzip -X -K matlab_R2020b_glnxa64.zip -d matlab_R2020b
   ```
3. 用 Nix 的 FHS shell 跑官方安装器：
   ```sh
   matlab-shell
   # 在 shell 内：
   cd matlab_R2020b
   ./install
   ```
   - 安装目标填 `~/MATLAB/R2020b`；
   - 用学校账号在线激活（会写 `~/.matlab/R2020b_licenses/`）。
4. 写入安装位置（Nix/HM 不托管该文件）：
   ```sh
   mkdir -p ~/.config/matlab
   echo 'INSTALL_DIR=$HOME/MATLAB/R2020b' > ~/.config/matlab/nix.sh
   ```
5. 退出 `matlab-shell`，验证：
   ```sh
   matlab -desktop
   ```

## 三、踩过的坑（都在启动器里写死了，别删）

- **安装器窗口不出来**：把安装包 `bin/glnxa64` 与 `sys/os/glnxa64` 下的
  `libstdc++.so.6*` 改名（例如加 `.distlink` 后缀）后重跑 `./install`。
- **装完 GUI 空白**：Niri 是纯 Wayland，MATLAB 只认 X11，需：
  - `QT_QPA_PLATFORM=xcb` 强制走 XWayland（Simulink 同）；
  - `LD_PRELOAD=/lib/libstdc++.so` 用 Nix 的新 libstdc++；
  - `LD_LIBRARY_PATH=/run/opengl-driver/lib/dri/`；
  - `-softwareopengl` 固定软件渲染；
  - 后台 `wmname LG3D` 打 WM_NAME hint，修无传统 WM 下的空白窗口。
- **Simulink 键盘输入失灵**：依赖里必须有 `libxkbcommon` + `xkeyboard_config`。
- **缩放**：`s.matlab.desktop.DisplayScaleFactor` 设小数无效——R2020b 用 Java 8，
  Linux 下只支持整数缩放。内屏 `scale 1.5` 下界面发糊是 XWayland 非整数缩放的
  固有限制；`Xft.dpi=144` 只影响字体，不改 `ScreenPixelsPerInch`。
  根治要么把 `outputs.kdl` 的 scale 改 1，要么升 R2025a+。
- **别用 `nix-matlab` 的 flake input**（见上）。

## 四、以后想恢复时

1. 把 `matlab.nix` 原样移回 `modules/nixos/programs/matlab.nix`：
   ```sh
   git mv modules/_trash/nixos/matlab.nix modules/nixos/programs/matlab.nix
   ```
   （如果届时已能改写/删除 `_trash` 内容；否则先复制再让用户决定，按仓库规则
   `_trash` 本身不允许删改。）
2. 在 `modules/nixos/programs/default.nix` 的 `imports` 里加回 `./matlab.nix`。
3. 按“二”重新下载、安装、写 `~/.config/matlab/nix.sh`。
4. 用户执行 `sudo nixos-rebuild switch --flake .#mynixos`。
5. 旧依赖名若已被 nixpkgs 改动（如 `gtk2` 被移除），按报错补/删 `matlabTargetPkgs`，
   或参考上游 `sceptri/nix-matlab` 的最新 `common.nix`（仓库只在注释里引用，没挂 input）。

## 五、本机清理记录（2026-10-19）

从配置中移除后，本机残留的手动安装内容（不属于 Nix、rebuild/GC 都不会动）：

| 路径 | 内容 |
| --- | --- |
| `~/MATLAB/R2020b` | 本体，约 4.1 GB |
| `~/.matlab/R2020b_licenses/` | 许可证文件 |
| `~/.config/matlab/nix.sh` | `INSTALL_DIR` 指向 |

是否删除由用户决定；删掉后仍可按本文件重装。

## 六、用 mpm 补装工具箱（Symbolic / Optimization 等）

MATLAB 本体之外的工具箱用 MathWorks 官方的 **mpm（MATLAB Package Manager）** 补装，
不要给工具箱单独建 Nix 包（同样是专有许可问题）。

1. 获取 mpm（单文件可执行，约 76 MB），放到 `~/mpm`：
   - 官方仓库：<https://github.com/mathworks/mpm>，按其 README 下载 Linux x64 版本。
   - 它是普通 ELF 二进制，依赖 `libpam.so.0` 等系统库，**必须在 `matlab-shell`（FHS）里运行**；
     在纯 Nix 环境直接执行会报 `libpam.so.0: cannot open shared object file`。
2. 在 `matlab-shell` 里查看/安装：
   ```sh
   matlab-shell
   # 进入 FHS shell 后：
   ~/mpm list --matlabroot=$HOME/MATLAB/R2020b
   ~/mpm install --release=R2020b --destination=$HOME/MATLAB/R2020b --products=Symbolic_Math_Toolbox
   ~/mpm install --release=R2020b --destination=$HOME/MATLAB/R2020b --products=Optimization_Toolbox
   ```
   - 产品名用**下划线**代替空格；多个产品用空格分隔，例如
     `--products=Symbolic_Math_Toolbox Optimization_Toolbox`。
   - 用的是学校许可、已激活的账号凭据，一般不会再要求登录。
   - 只想下载不安装可用 `mpm download`；R2022b 及更早版本可用 `--doc` 一并装文档。
3. 验证（新起 `matlab` 进程会自动重新扫描工具箱；GUI 若安装时开着需重启）：
   ```sh
   matlab -batch "which('lsqcurvefit')"            # Optimization Toolbox
   matlab -batch "syms x; limit(sin(x)/x,x,0)"    # Symbolic Math Toolbox
   ```
4. 其它常用产品名：`Statistics_and_Machine_Learning_Toolbox`、
   `Deep_Learning_Toolbox`、`Global_Optimization_Toolbox`、
   `Partial_Differential_Equation_Toolbox` 等。
