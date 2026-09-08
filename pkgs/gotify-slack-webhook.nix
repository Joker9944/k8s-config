{
  flake,
  lib,
  stdenvNoCC,
  buildGoModule,
  fetchFromGitHub,
  jq,
  gotify-server,
  ...
}:
buildGoModule (finalAttrs: {
  pname = "gotify-slack-webhook";
  version = "2025.11.1";

  src = stdenvNoCC.mkDerivation {
    name = "${finalAttrs.pname}-updated-src-${finalAttrs.version}";

    outputHash = "sha256-uQmz3UOJIujPA7tDmmw/0gKDt95fbUxhzpM2QzloCHs=";
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";

    src = fetchFromGitHub {
      owner = "LukasKnuth"; # cSpell:ignore Lukas
      repo = finalAttrs.pname;
      rev = finalAttrs.version;
      sha256 = "sha256-5Eb/67H0MMCEUq4gBK0qI+Nxvu/qisxUQuHBv3sqjs4=";
    };

    nativeBuildInputs = finalAttrs.goModules.nativeBuildInputs ++ [
      flake.packages.${stdenvNoCC.hostPlatform.system}.gomod-cap
      jq
    ];

    inherit (finalAttrs) modRoot;
    inherit (finalAttrs.goModules) configurePhase;

    postConfigure = ''
      cp ${gotify-server.src}/go.mod gotify-server.mod
    '';

    buildPhase = ''
      runHook preBuild

      # Syncs the downloaded server lockfile with the local one to make plugin binary compatible
      gomod-cap -from gotify-server.mod -to go.mod

      # Sync Toolchain and Go language versions as well
      go mod edit -go $(go mod edit -json gotify-server.mod | jq -r '.Go')
      go mod edit -toolchain $(go mod edit -json gotify-server.mod | jq -r '.Toolchain')
      go mod tidy

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r . $out

      runHook postInstall
    '';
  };

  vendorHash = "sha256-rLFcZyO0iNIQ11qT4u/1sMykN08CyZiMeJLHrFW9FeI=";

  env = {
    CGO_ENABLED = "1";
  };

  buildPhase = ''
    runHook preBuild

    go build \
      -a \
      -installsuffix=cgo \
      -ldflags="-w -s" \
      -buildmode=plugin \
      -o ${finalAttrs.pname}.so \
      .

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/gotify/plugins
    cp -r *.so $out/lib/gotify/plugins/

    runHook postInstall
  '';

  meta = {
    description = "A Gotify Plugin to accept Slack Incoming Webhooks";
    homepage = "https://github.com/LukasKnuth/gotify-slack-webhook";
    license = lib.licenses.mit;
  };
})
