{
  description = "NFX - Algebraic Effects System with Handlers in pure Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: import ./nix/outputs.nix inputs;
}
