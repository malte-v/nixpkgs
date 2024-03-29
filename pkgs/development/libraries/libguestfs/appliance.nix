{ lib
, stdenvNoCC
, vmTools
}:

vmTools.runInLinuxImage (stdenvNoCC.mkDerivation {
  pname = "libguestfs-appliance";
  version = "1.48.6";

  diskImage = vmTools.diskImageExtraFuns.debian12aarch64 [
    "libguestfs-tools"
    "linux-image-arm64" # required by supermin
  ];
  diskImageFormat = "qcow2";
  memSize = "2048"; # we need to be generous here

  unpackPhase = "true";

  installPhase = ''
    runHook preInstall

    LIBGUESTFS_DEBUG=1 libguestfs-make-fixed-appliance $out || true
    cp /tmp/.guestfs-0/appliance.d/* $out
    chmod +x $out/kernel
    touch $out/README.fixed

    runHook postInstall
  '';

  meta = with lib; {
    description = "VM appliance disk image used in libguestfs package";
    homepage = "https://libguestfs.org";
    license = with licenses; [ gpl2Plus lgpl2Plus ];
    platforms = [ "aarch64-linux" ]; # TODO
    hydraPlatforms = [ ]; # Hydra fails with "Output limit exceeded"
  };
})
