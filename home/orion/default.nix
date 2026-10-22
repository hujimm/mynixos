{
  ...
}:
{
  imports = [
    ../../modules/hm/desktop
    ../../modules/hm/i18n
    ../../modules/hm/programs
    ../../modules/hm/ai-agent
    ../../modules/hm/security
  ];

  home.stateVersion = "26.05";

  # billion-context 的 bili 命令装在用户级 npm prefix 下
  home.sessionPath = [ "$HOME/.local/bin" ];
}
