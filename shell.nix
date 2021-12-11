with import <nixpkgs> {};
let
     pkgs = import (builtins.fetchGit {
         # Descriptive name to make the store path easier to identify
         name = "ghc";
         url = "https://github.com/NixOS/nixpkgs/";
         ref = "refs/heads/nixpkgs-unstable";
         rev = "92a047a6c4d46a222e9c323ea85882d0a7a13af8";
     }) {};

     myPkg = pkgs.ghc;
in

pkgs.stdenv.mkDerivation rec {
  name = "dev-env";
  pure = false;
  buildInputs = with pkgs; [
    freeglut
    libGLU
    libGL
    ghc
  ];
  LD_LIBRARY_PATH = with pkgs; "${freeglut}/lib/run/opengl-driver/lib:/run/opengl-driver-32/lib";
}
