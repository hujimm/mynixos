{
  pkgs,
  inputs,
  config,
  ...
}:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  environment.systemPackages = [ pkgs.sops ];

  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    defaultSopsFile = ./secrets/api-key.yaml;

    # orion 登录密码 hash（mkpasswd -s 生成，绝不能放明文密码）。
    # neededForUsers：解密提前到用户创建之前，落到 /run/secrets-for-users/，
    # 由 core/users.nix 的 hashedPasswordFile 引用
    secrets."orion-password-hash" = {
      neededForUsers = true;
    };

    # GitHub token（复用 gh auth 的 token），给 nix 拉取 github: 输入时认证，
    # 避免匿名按 IP 限流。裸 token 存 secret，经下方模板渲染成完整配置行。
    secrets."github-token" = { };

    # EasyTier 网络口令见 ./easytier-secret.nix（桌面/aliyun/lightsail 共用）。

    # 模板：拼出 "access-tokens = github.com=<token>" 整行，由 nix.extraOptions
    # 的 !include 引入。nix 的 access-tokens 不支持 file: 前缀（NixOS/nix#6536
    # 未实现），include 是社区验证过的替代方案。放 users 组可读：
    # 用户级 nix 命令由 orion 进程发起。
    templates."nix-access-tokens" = {
      content = "access-tokens = github.com=${config.sops.placeholder."github-token"}";
      group = "users";
      mode = "0440";
    };
  };

  # 系统解密与 sops 编辑共用 /var/lib/sops-nix/key.txt：
  # 放开给 users 组读取(orion 在 wheel 里本就等价可读)，重装后无需手动 chmod
  systemd.tmpfiles.rules = [
    "Z /var/lib/sops-nix/key.txt 0640 root users - -"
  ];
}
