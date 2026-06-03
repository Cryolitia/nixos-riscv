{
  lib,
  stdenv,
  kernel,
}:

stdenv.mkDerivation {
  pname = "w1-gpio-custom";
  version = "0-unstable";

  src = ./.;

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "ARCH=${stdenv.hostPlatform.linuxArch}"
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "KERNEL_SRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall

    install *.ko -Dm444 -t $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/w1-gpio-custom

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://github.com/openwrt/archive/blob/master/package/kernel/w1-gpio-custom/src/w1-gpio-custom.c";
    license = with licenses; [ gpl2Plus ];
    maintainers = with maintainers; [ Cryolitia ];
    platforms = platforms.linux;
  };
}
