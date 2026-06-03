{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "duo-utils";
  version = "1.0";
  src = ./duo-utils;

  buildInputs = [
  ];

  # Build Phases
  configurePhase = "";
  buildPhase = "";
  installPhase = ''
    mkdir -p "$out/bin"
    for f in ./**.sh; do cp "$f" $out/bin/$(basename "''${f%.sh}"); done
    chmod 777 $out/bin/*
    patchShebangs --build $out/bin
  '';
  meta = with pkgs.lib; {
    description = "The scripts of the official buildroot repo";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
