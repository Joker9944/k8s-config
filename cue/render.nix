{
  lib,
  stdenvNoCC,
  cue,
}:
let
  # probe/, graph/ and generate.sh are named nowhere, so editing them cannot
  # rebuild an artifact.
  srcFor =
    parts:
    lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions ([ ./cue.mod ] ++ parts);
    };

  # cue.mod/module.cue declares no deps and cue.mod/gen is vendored, so
  # evaluation needs no network and this is an ordinary derivation.
  render =
    {
      name,
      description,
      command,
      instance,
      src,
      expect,
    }:
    stdenvNoCC.mkDerivation {
      inherit name src;

      nativeBuildInputs = [ cue ];

      dontConfigure = true;
      doCheck = true;

      buildPhase = ''
        runHook preBuild

        cue cmd --inject out=render ${command} ${instance}

        runHook postBuild
      '';

      checkPhase = ''
        runHook preCheck

        for path in ${lib.escapeShellArgs expect}; do
          test -e "render/$path" || {
            echo "rendered tree is missing $path" >&2
            exit 1
          }
        done

        runHook postCheck
      '';

      installPhase = ''
        runHook preInstall

        mkdir $out
        cp -r render/* $out

        runHook postInstall
      '';

      meta = { inherit description; };
    };
in
{
  # The command writes the artifact root at <out>, so the output is an OCI
  # artifact as it stands, and publishing copies it out of the store rather
  # than reshaping it.
  nyxManifests = render {
    name = "cue-render-nyx-manifests";
    description = "Rendered manifests for the nyx cluster";
    command = "render";
    instance = "./manifests";
    src = srcFor [
      ./schema
      ./apps
      ./infrastructure
      ./manifests
    ];
    # what the level-2 Kustomization reconciles
    expect = [ "sync" ];
  };

  # The level-2 Kustomization and its OCIRepository, which are committed to git
  # rather than shipped in an artifact, so $out keeps mirroring the repo path.
  # Nothing under clusters/ imports schema.
  bootstrap = render {
    name = "cue-render-bootstrap";
    description = "Rendered Flux bootstrap layer";
    command = "bootstrap";
    instance = "./clusters/nyx/flux";
    src = srcFor [ ./clusters ];
    expect = [ "clusters/nyx/flux" ];
  };
}
