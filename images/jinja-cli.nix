{
  flake,
  stdenv,
  dockerTools,
  jinja2-cli,
  ...
}:
dockerTools.buildLayeredImage {
  name = "jinja-cli";
  tag = "4.0.0";

  fromImage = flake.packages.${stdenv.hostPlatform.system}.base;

  contents = [ jinja2-cli ];

  config = {
    User = "65534";

    Entrypoint = [
      "sh"
      "-c"
      "jinja2"
    ];
  };
}
