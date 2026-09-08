{
  lib,
  stdenvNoCC,
  cue,
}:
let
  # The module and the tool file that defines the workflow commands. Every
  # instance needs both; nothing else is shared by all of them. probe/ and
  # generate.sh are named nowhere, so editing them cannot rebuild an artifact.
  shared = [
    ./cue.mod
    ./render_tool.cue
  ];

  # Only the instance being rendered enters its own source, so a workload edit
  # rebuilds its tier and nothing else. No .cue file imports across a tier
  # boundary, which is what makes that sound.
  srcFor =
    parts:
    lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions (shared ++ parts);
    };

  # A tier is a directory holding a .cue file named after it.
  tiersIn =
    tree:
    lib.pipe (builtins.readDir (./. + "/${tree}")) [
      (lib.filterAttrs (
        name: type: type == "directory" && builtins.pathExists (./. + "/${tree}/${name}/${name}.cue")
      ))
      lib.attrNames
      (map (name: {
        inherit tree name;
      }))
    ];

  tiers = tiersIn "apps" ++ tiersIn "infrastructure";

  # cue.mod/module.cue declares no deps and cue.mod/gen is vendored, so
  # evaluation needs no network and this is an ordinary derivation.
  render =
    {
      name,
      description,
      command,
      instance,
      src,
      subdir ? "",
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
          test -e "render/${subdir}/$path" || {
            echo "rendered tree is missing $path" >&2
            exit 1
          }
        done

        runHook postCheck
      '';

      installPhase = ''
        runHook preInstall

        mkdir $out
        cp -r render/${subdir}/* $out

        runHook postInstall
      '';

      meta = { inherit description; };
    };
in
{
  # One derivation per tier. The command writes <out>/<tree>/<tier>, so that
  # subtree is what lands in $out: the output is an OCI artifact root as it
  # stands, and publishing copies it out of the store rather than reshaping it.
  perTier = lib.listToAttrs (
    map (
      { tree, name }:
      lib.nameValuePair "cue-render-${name}" (render {
        name = "cue-render-${name}";
        description = "Rendered manifests for the ${name} tier";
        command = "render";
        instance = "./${tree}/${name}";
        src = srcFor [
          ./schema
          (./. + "/${tree}/${name}")
        ];
        subdir = "${tree}/${name}";
        # what the level-2 Kustomization reconciles
        expect = [ "sync" ];
      })
    ) tiers
  );

  # The level-2 Kustomizations and OCIRepositories, which are committed to git
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
