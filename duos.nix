{
  inputs,
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

# The cv1813hXXX_milkv_duos_sd.dtb and fip-duos.bin (aka fip.bin) files in
# the prebuilt/ dir used by this module were generated on Debian via "./build.sh
# lunch" within a fork of Milk V's duo-buildroot-sdk repo at
# https://github.com/mcdonc/duo-buildroot-sdk/tree/nixos-riscv . The fork is
# trivial: four lines were changed to allow dynamic kernel params to be passed
# down to the kernel and to NixOS and to increase available RAM by changing
# ION_SIZE.  The cv1813h_milkv_duos_sd.dtc file in the prebuilt/ dir was
# generated from the cv1813h_milkv_duos_sd.dtb using

# dtc -I dtb  -O dts -o cv1813h_milkv_duos_sd.dts  -@ ~/duo-buildroot-sdk/linux_5.10/build/cv1813h_milkv_duos_sd/arch/riscv/boot/dts/cvitek/cv1813h_milkv_duos_sd.dtb

# The fip.bin file was taken from fsbl/build/cv1813h_milkv_duos_sd/fip.bin
#
# The kernel config file was reused from duo256
#
# If stage 2 of the boot from SD fails to boot automatically, it can be booted
# manually. via the U-Boot CLI:

# cv181x_c906# setenv othbootargs ${othbootargs} init=/nix/store/6qq6m4i6zb153nywy5qwr5v33akbzrxk-nixos-system-nixos-24.05.20240215.69c9919/init
# cv181x_c906# boot

# obviously the /nix/store path might be different, but doing

# cv181x_c906# setenv othbootargs ${othbootargs} boot.shell_on_fail
# cv181x_c906# boot

# will let you drop into a prompt to find it in /mnt-root/nix/store

let
  duo-buildroot-sdk = pkgs.fetchFromGitHub {
    owner = "milkv-duo";
    repo = "duo-buildroot-sdk-v2";
    tag = "v2.0.1";
    hash = "sha256-+57afhR4Ydh2716/AwgA1vQQSs3PtnB/NzH2Y5lIHVs=";
  };

  version = "5.10.4";
  src = "${duo-buildroot-sdk}/linux_${lib.versions.majorMinor version}";

  configfile = pkgs.writeText "milkv-duo-256-linux-config" (
    builtins.readFile ./prebuilt/duo-s-kernel-config.txt
  );

  aic8800-shutup = pkgs.fetchpatch2 {
    name = "kernel-reduce-aic8800-logs";
    url = "https://github.com/milkv-duo/duo-buildroot-sdk-v2/commit/951812468d912db10c3acad2cefb0974d4e86d28.patch";
    hash = "sha256-z3Ko5OXEel8MyB0AZD36e29iD3YAXYXNnQXzUMXFSjI=";
  };

  kernel =
    (pkgs.linuxManualConfig {
      inherit version src configfile;
      allowImportFromDerivation = true;
    }).overrideAttrs
      (oldAttrs: {
        preConfigure = ''
          patch -Np2 -i ${aic8800-shutup}

          substituteInPlace arch/riscv/Makefile \
            --replace '-mno-ldd' "" \
            --replace 'KBUILD_CFLAGS += -march=$(riscv-march-cflags-y)' \
                      'KBUILD_CFLAGS += -march=$(riscv-march-cflags-y)_zicsr_zifencei -fno-asynchronous-unwind-tables -fno-unwind-tables' \
            --replace 'KBUILD_AFLAGS += -march=$(riscv-march-aflags-y)' \
                      'KBUILD_AFLAGS += -march=$(riscv-march-aflags-y)_zicsr_zifencei'
          substituteInPlace arch/riscv/mm/context.c \
            --replace sptbr CSR_SATP
        '';

        preFixup = (oldAttrs.preFixup or "") + ''
          TARGET_MAKEFILE=$(find $dev -name Makefile | grep "arch/riscv/Makefile" | head -n 1)

          if [ -n "$TARGET_MAKEFILE" ]; then
            echo "Found target Makefile at: $TARGET_MAKEFILE"
            chmod +w "$TARGET_MAKEFILE"
            
            substituteInPlace "$TARGET_MAKEFILE" --replace "prepare: vdso_prepare" "prepare:"
            
            echo "Successfully patched $TARGET_MAKEFILE"
          else
            echo "ERROR: Could not find arch/riscv/Makefile in $dev"
            exit 1
          fi
        '';
      });
  duo_overlay = import ./overlays/duo.nix;

in
{
  disabledModules = [
    "profiles/all-hardware.nix"
  ];

  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  nixpkgs = {
    localSystem.config = "x86_64-unknown-linux-gnu";
    crossSystem.config = "riscv64-unknown-linux-gnu";
    overlays = [
      (final: super: {
        makeModulesClosure = x: super.makeModulesClosure (x // { allowMissing = true; });
      })
      duo_overlay
    ];
  };

  boot.kernelPackages = pkgs.linuxPackagesFor kernel;
  boot.kernelPatches = [
    {
      name = "add-remoteproc-and-burn-support";
      patch = ./prebuilt/0001-add-remoteproc-and-burn-support.patch;
    }
    {
      name = "st7796";
      patch = ./prebuilt/0001-st7796.patch;
    }
  ]
  ;

  boot.kernelParams = [
    "console=ttyS0,115200"
    "earlycon=sbi"
    "riscv.fwsz=0x80000"
    "blkdevparts=mmcblk0:63360K(BOOT),2048K(MISC),128K(ENV),-(ROOTFS);mmcblk0boot0:1M(fip),1M(fip_bak);"
    "root=/dev/mmcblk0p4"
    "rootwait"
    "rw"
    "cma=16M"
  ];
  boot.consoleLogLevel = 9;

  boot.loader = {
    grub.enable = false;
  };

  boot.initrd.enable = false;

  boot.kernel.sysctl = {
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
    "vm.page-cluster" = 0;
    "vm.swappiness" = 180;
    "kernel.pid_max" = 4096 * 8; # PAGE_SIZE * 8
  };

  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ./kmod/saradc/package.nix { })
    (config.boot.kernelPackages.callPackage ./kmod/rtc/package.nix { })
    (config.boot.kernelPackages.callPackage ./kmod/w1-gpio-custom/package.nix { })
  ];

  boot.kernelModules = [
    "aic8800_bsp"
    "aic8800_fdrv"
    "cv181x_saradc"
    "cv181x_rtc"
  ];

  system.stateVersion = "25.05";

  system.build.dtb =
    pkgs.runCommand "duos.dtb"
      {
        nativeBuildInputs = [ pkgs.dtc ];
      }
      ''
        dtc -I dts -O dtb -o "$out" ${pkgs.writeText "duos.dts" ''
          /include/ "${./prebuilt/cv1813h_milkv_duos_sd.dts}"
          / {
            chosen {
              bootargs = "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}";
            };
          };
        ''}
      '';

  system.build.its = pkgs.writeText "cv181x.its" ''
    /dts-v1/;

    / {
      description = "Various kernels, ramdisks and FDT blobs";
      #address-cells = <2>;

      images {
        kernel-1 {
          description = "kernel";
          type = "kernel";
          data = /incbin/("${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}");
          arch = "riscv";
          os = "linux";
          compression = "none";
          load = <0x00 0x80200000>;
          entry = <0x00 0x80200000>;
          hash-2 {
            algo = "crc32";
          };
        };

        fdt-1 {
          description = "flat_dt";
          type = "flat_dt";
          data = /incbin/("${config.system.build.dtb}");
          arch = "riscv";
          compression = "none";
          hash-1 {
            algo = "sha256";
          };
        };
      };

      configurations {
        default = "config-sg2000_milkv_duos_musl_riscv64_emmc";
        config-sg2000_milkv_duos_musl_riscv64_emmc {
          description = "boot cvitek system with board cv1812h_milkv_duos";
          kernel = "kernel-1";
          fdt = "fdt-1";
        };
      };
    };
  '';

  system.build.bootsd =
    pkgs.runCommand "boot.sd"
      {
        nativeBuildInputs = [
          pkgs.ubootTools
          pkgs.dtc
        ];
      }
      ''
        mkimage -f ${config.system.build.its} "$out"
      '';

  hardware.enableAllFirmware = false;

  hardware.enableAllHardware = lib.mkForce false;

  hardware.enableRedistributableFirmware = false;

  # NOTE: setting hardware.firmwareCompression = "none"is required because the aic8800_fdrv driver module cannot load xz compressed files. If set to xz or zstd, adding the aic8800 firmware to hardware.firmware automatically compresses the files, which in turn will make loading the aic8800_fdrv driver module fail.
  hardware.firmwareCompression = "none";

  hardware.firmware = [
    (pkgs.stdenv.mkDerivation {
      name = "wlan-aic8800-firmware";
      src = "${duo-buildroot-sdk}/device/generic/rootfs_overlay/duos/mnt/system/firmware/aic8800/";
      installPhase = ''
        mkdir -p $out/lib/firmware/aic8800
        cp $src/fw_patch_table_8800d80_u02.bin $out/lib/firmware/aic8800/
        cp $src/fw_patch_8800d80_u02.bin $out/lib/firmware/aic8800/
        cp $src/lmacfw_rf_8800d80_u02.bin $out/lib/firmware/aic8800/
        cp $src/aic_userconfig_8800d80.txt $out/lib/firmware/aic8800/
        cp $src/fw_adid_8800d80_u02.bin $out/lib/firmware/aic8800/
        cp $src/fmacfw_8800d80_u02.bin $out/lib/firmware/aic8800/
      '';
    })
  ];

  services.zram-generator = {
    enable = true;
    settings.zram0 = {
      compression-algorithm = "zstd";
      zram-size = "ram * 2";
    };
  };

  boot.initrd.systemd.root = null;

  users.users.root.initialPassword = "milkv";
  services.getty.autologinUser = "root";
  users.motd = "Welcome to the milkv duo module 01!";

  services.udev.enable = false;
  services.nscd.enable = false;
  nix.enable = true;
  system.nssModules = lib.mkForce [ ];

  networking = {
    hostName = "milkv-module-01-nixos";
    firewall.enable = false;
    networkmanager.enable = true;
  };

  # configure usb0 as an host device
  systemd.tmpfiles.settings = {
    "10-cviusb" = {
      "/proc/cviusb/otg_role".w.argument = "host";
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  # generating the host key takes a while
  systemd.services.sshd.serviceConfig = {
    TimeoutStartSec = 120;
  };

  environment.systemPackages = with pkgs; [
    fastfetch
    usbutils
    inetutils
    iproute2
    helix
    i2c-tools
    duo-utils
    duo-pinmux
    spidev-test
    gcc
    gnumake
    libgpiod
    lgpio
    vim
    alsa-utils
    evtest
    wchisp
    btop
    libdrm
    (mpv.override {
      youtubeSupport = false;
    })

    (python3.withPackages (
      ps: with ps; [
        python
        spidev
        pillow
        numpy
        gpiozero
        gpiod
        lgpio
        smbus2
        w1thermsensor
      ]
    ))
  ];

  programs.less.lessopen = null;

  sdImage = {
    firmwareSize = 64;
    populateRootCommands = "";
    populateFirmwareCommands = ''
      cp ${./prebuilt/fip-duos.bin}  firmware/fip.bin
      cp ${config.system.build.bootsd} firmware/boot.sd
    '';
  };

  sdImage.expandOnBoot = true;
  systemd.services.expand-root-partition.script = lib.mkForce ''
    ${lib.getExe' pkgs.e2fsprogs "resize2fs"} /dev/mmcblk0p4
  '';

  nix = {
    settings = {
      narinfo-cache-positive-ttl = 60 * 60 * 24;
      trusted-users = [
        "root"
        "@wheel"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      nix-path = lib.mapAttrsToList (name: path: "${name}=${path}") inputs;

      substituters = [
        "https://mirrors.mirrorz.org/nix-channels/store"
        "https://cache.nixos.org/"

        "https://nix-community.cachix.org"
        "https://cryolitia.cachix.org"
        "http://cache.cryolitia.dn42"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cryolitia.cachix.org-1:/RUeJIs3lEUX4X/oOco/eIcysKZEMxZNjqiMgXVItQ8="
        "kp920.cryolitia.dn42:M68UcYMNX/2yWXFwDb21jAregdcIsF3uIrSmXldX70k="
      ];

      fallback = true;

      # Disable the built-in flake registry to speed up evaluation
      flake-registry = "";
    };

    # This is important. It locks nixpkgs registry used in nix shell
    # to the same of flakes. Saves time.
    registry = ({ pkgs.flake = inputs.self; } // lib.mapAttrs (_: flakes: { flake = flakes; }) inputs);

    # make `nix run nixpkgs#nixpkgs` use the same nixpkgs as the one used by this flake.
    channel.enable = false; # remove nix-channel related tools & configs, we use flakes instead.
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # _TODO_
  system.requiredKernelConfig = lib.mkForce [ ];
}
