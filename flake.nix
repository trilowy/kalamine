# On NixOS, install direnv and nix-direnv to auto load the flake when entering the project directory
{
  description = "Zig project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
    };
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        zig_0_16
        zls_0_16 # Zig LSP
      ];
    };
  };
}
