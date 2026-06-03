{
  lib,
  stdenv,
  kernel,
}:

stdenv.mkDerivation {
  pname = "cv181x_saradc";
  version = "0-unstable";

  src = lib.cleanSource ./.;

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "ARCH=${stdenv.hostPlatform.linuxArch}"
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "KERNEL_SRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall

    install *.ko -Dm444 -t $out/lib/modules/${kernel.modDirVersion}/kernel/drivers/cv181x_saradc

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://github.com/milkv-duo/duo-buildroot-sdk-v2/blob/main/osdrv/interdrv/saradc";
    license = with licenses; [ gpl2Plus ];
    maintainers = with maintainers; [ Cryolitia ];
    platforms = [ "riscv64-linux" ];
  };
}
