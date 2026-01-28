{
  flake,
  stdenv,
  dockerTools,
  postgresql,
  ...
}:
dockerTools.buildLayeredImage {
  name = "postgresql-client";
  tag = "4.0.0";

  fromImage = flake.packages.${stdenv.hostPlatform.system}.base;

  contents = [ postgresql ];

  config = {
    User = "65534";

    Entrypoint = [
      "sh"
      "-c"
      "psql"
    ];
  };
}
