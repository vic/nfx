{ pkgs, docs }:
let
  inherit (pkgs) lib;
in
pkgs.stdenv.mkDerivation {
  name = "nfx-mdbook";
  
  src = ./../book;
  
  nativeBuildInputs = [ pkgs.mdbook ];
  
  buildPhase = ''
    # Copy book configuration
    cp -r $src/* .
    
    # Copy generated docs into src/
    rm -rf src/*
    cp -r ${docs}/* src/
    
    # Build the book
    mdbook build
  '';
  
  installPhase = ''
    cp -r book $out
  '';
}
