_: {
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "hujimm";
        email = "orionli2006@gmail.com";
      };

      # 常见项：新分支裸 push 自动建上游、pull 走 rebase、fetch 清理已删分支引用
      push.default = "simple";
      push.autoSetupRemote = true;
      pull.rebase = true;
      merge.conflictStyle = "zdiff3";
      rerere.enabled = true;
      rebase.autoStash = true;
      fetch.prune = true;
      init.defaultBranch = "main";
    };
  };

  # GitHub CLI：auth 后自动配置 git credential helper，push/pull 免密
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      # 关闭匿名使用数据上报（gh 2.97 默认 enabled）
      telemetry = "disabled";
      aliases = {
        co = "pr checkout";
        pv = "pr view";
        prs = "pr status";
      };
    };
  };
}
