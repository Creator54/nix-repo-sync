{
  description = "A NixOS module for syncing git repositories and creating configuration symlinks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    {
      # NixOS module for declarative configuration
      nixosModules.default = import ./module.nix;
      
      # Library function for advanced use cases
      lib = import ./lib.nix;
    };
}
