{
  config,
  ...
}:
{
  home.file.".config/sops/age/keys.txt".source =
    config.lib.file.mkOutOfStoreSymlink "/var/lib/sops-nix/key.txt";

  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    defaultSopsFile = ../../nixos/security/secrets/api-key.yaml;
    secrets."wallhaven-api-key" = { };
  };
}
