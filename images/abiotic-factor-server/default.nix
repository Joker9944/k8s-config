{
  flake,
  lib,
  stdenv,
  dockerTools,
  wine64Packages,
  writeTextFile,
  ...
}:
let
  port = 7777;
  queryPort = 27015;
in
dockerTools.buildLayeredImage {
  name = "abiotic-factor-server";
  tag = "1.0.3";

  fromImage = flake.packages.${stdenv.hostPlatform.system}.base;

  contents = [
    wine64Packages.stable
    (writeTextFile {
      name = "entrypoint";
      executable = true;
      destination = "/bin/abiotic-factor-server";
      text = lib.readFile ./files/abiotic-factor-server.sh;
      checkPhase = ''
        ${stdenv.shellDryRun} "$target"
      '';
    })
  ];

  enableFakechroot = true;
  fakeRootCommands = ''
    mkdir -p /home/steam
    chown 65534:65534 /home/steam
    chmod 1777 /home/steam
  '';

  config = {
    User = "65534";

    Env = [
      "HOME=/home/steam"
      "WINEPREFIX=/home/steam/wine/.wine"
      "WINEDEBUG=fixme-all" # Disable all FIXME messages since they just pollute the log output
      "MAX_PLAYERS=6"
      "PORT=${toString port}"
      "QUERY_PORT=${toString queryPort}"
      "SERVER_NAME=LinuxServer"
      "SERVER_PASSWORD=password"
      "USE_PERF_THREADS=true"
      "NO_ASYNC_LOADING_THREAD=false"
    ];

    ExposedPorts = {
      "${toString port}/udp" = { };
      "${toString queryPort}/udp" = { };
    };

    Entrypoint = [ "abiotic-factor-server" ];
  };
}
