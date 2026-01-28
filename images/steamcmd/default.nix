{
  flake,
  stdenv,
  dockerTools,
  pkgsi686Linux,
  steamcmd,
  ...
}:
dockerTools.buildLayeredImage {
  name = "steamcmd";
  tag = "1.0.0";

  fromImage = flake.packages.${stdenv.hostPlatform.system}.base;

  contents = [
    pkgsi686Linux.glibc.out
    (steamcmd.overrideAttrs (_: {
      buildInputs = [ ];

      installPhase = ''
        runHook preInstall

        mkdir -p $out/lib/steamcmd/linux32
        install -Dm755 steamcmd.sh $out/lib/steamcmd
        install -Dm755 linux32/* $out/lib/steamcmd/linux32

        mkdir -p $out/bin
        install -Dm755 ${./files/steamcmd.sh} $out/bin/steamcmd

        runHook postInstall
      '';
    }))
  ];

  enableFakechroot = true;
  fakeRootCommands = ''
    mkdir -p /home/steam
    chown 65534:65534 /home/steam
    chmod 1777 /home/steam
  '';

  config = {
    User = "65534";

    Env = [ "HOME=/home/steam" ];

    Entrypoint = [ "steamcmd" ];
  };
}
