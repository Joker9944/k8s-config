{
  flake,
  stdenv,
  dockerTools,
  kubectl,
  python3Minimal,
  rclone,
  ...
}:
dockerTools.buildLayeredImage {
  name = "backup-runner";
  tag = "1.0.0";

  fromImage = flake.packages.${stdenv.hostPlatform.system}.base;

  contents = [
    kubectl
    python3Minimal # runs the backup scripts; stdlib only, no packages
    rclone
  ];

  config = {
    User = "65534";

    Entrypoint = [ "bash" ];
  };
}
