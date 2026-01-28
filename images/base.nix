{
  dockerTools,
  bash,
  coreutils,
  curl,
  procps,
  gnutar,
  gzip,
  findutils,
  tzdata,
  ...
}:
dockerTools.buildLayeredImage {
  name = "base";
  tag = "1.0.0";

  contents = [
    # Utilities
    dockerTools.fakeNss # Setup basic passwd and groups file
    dockerTools.usrBinEnv # Setup /usr/bin/env for script usage
    dockerTools.caCertificates
    # Programs
    bash # Some apps / scripts require bash
    coreutils # All the core commands like ls, test, mkdir, etc.
    curl # Health checks
    procps # Health checks
    gnutar # Required for `kubectl cp`
    gzip # Required for `kubectl cp`
    findutils # Required for scripting
    tzdata # Allows for timezones to be set
  ];

  enableFakechroot = true;
  fakeRootCommands = ''
    mkdir /tmp
    chmod 1777 /tmp
  '';

  config = {
    User = "65534";

    Env = [ "TZ=UTC" ];

    Entrypoint = [ "bash" ];
  };
}
