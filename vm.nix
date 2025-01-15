{ pkgs, ... }: {
  boot.kernelPackages = pkgs.linuxPackages_latest;
   imports = [
    ./nixos/modules/services/misc/speedtest-tracker.nix
  ];
  services.speedtest-tracker = {
    appKeyFile = "${pkgs.writeText "keyfile" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}";
    enable = true;
    hostname = "speedtest-tracker.example.com";
  };
  nixpkgs.hostPlatform = "x86_64-linux";
}
