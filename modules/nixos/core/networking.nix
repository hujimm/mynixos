{ ... }:
{
  networking = {
    networkmanager.enable = true;
    hostName = "mynixos";

    firewall.enable = true;
    firewall.allowedTCPPorts = [ 49374 ];
    firewall.checkReversePath = "loose";
  };

}
