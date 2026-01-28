{
  flake,
  stdenv,
  dockerTools,
  buildEnv,
  gotify-server,
  ...
}:
let
  port = 80;
  pluginsDir = "/plugins";
in
dockerTools.buildLayeredImage {
  name = "gotify-custom";
  tag = "3.0.0";

  fromImage = flake.packages.${stdenv.hostPlatform.system}.base;

  contents = [
    gotify-server
    (buildEnv {
      name = "plugins-overlay";
      extraPrefix = pluginsDir;
      paths = [
        "${flake.packages.${stdenv.hostPlatform.system}.gotify-slack-webhook}/lib/gotify/plugins"
      ];
    })
  ];

  enableFakechroot = true;
  fakeRootCommands = ''
    mkdir /data
    chown 65534:65534 /data
  '';

  config = {
    User = "65534";

    Env = [
      "GOTIFY_SERVER_PORT=${toString port}"
      "GOTIFY_PLUGINSDIR=${pluginsDir}" # cSpell:ignore PLUGINSDIR
    ];

    Healthcheck = {
      Test = [
        "CMD"
        "curl --fail http://localhost:$GOTIFY_SERVER_PORT/health || exit 1"
      ];
      Interval = 30000000000; # 30s
      Timeout = 5000000000; # 5s
      StartInterval = 5000000000; # 5s
    };

    ExposedPorts = {
      "${toString port}/tcp" = { };
    };

    Entrypoint = [ "server" ];
  };
}
