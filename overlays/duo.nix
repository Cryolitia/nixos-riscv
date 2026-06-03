# duo.nix
self: super: {
  duo-utils = import ./duo-utils.nix { pkgs = super; };
  duo-pinmux = import ./duo-pinmux.nix {
    pkgs = super;
  };
  spidev-test = import ./spi-test.nix {
    pkgs = super;
  };
}
