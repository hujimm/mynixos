{
  pkgs,
  ...
}:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = false; # 玩游戏要开

    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };
  services.libinput.enable = true;

  hardware.enableRedistributableFirmware = true;
  # 如果 WiFi 还是不行，再加下面这行（需要 allowUnfree）
  # hardware.enableAllFirmware = true;

  hardware.cpu.intel.updateMicrocode = true;
  services.thermald.enable = true;
  services.fwupd.enable = true;

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };
}
