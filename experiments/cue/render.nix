{
  lib,
  stdenvNoCC,
  cue,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    # the gate, its allowlist and the notes are migration scaffolding; nothing
    # the render reads, and a change to them should not rebuild an artifact
    fileset = lib.fileset.unions [
      ./cue.mod
      ./schema
      ./apps
      ./infrastructure
      ./clusters
      ./render_tool.cue
    ];
  };

  # A tier is a directory holding a .cue file named after it — the same rule
  # gate.py discovers them by.
  tiersIn =
    tree:
    lib.pipe (builtins.readDir (src + "/${tree}")) [
      (lib.filterAttrs (
        name: type: type == "directory" && builtins.pathExists (src + "/${tree}/${name}/${name}.cue")
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
      pname,
      command,
      instance,
    }:
    stdenvNoCC.mkDerivation {
      inherit pname src;
      version = "0";
      nativeBuildInputs = [ cue ];
      dontConfigure = true;
      dontInstall = true;
      buildPhase = ''
        cue cmd --inject out=$out ${command} ${instance}
      '';
      meta.description = name;
    };
in
{
  # One derivation per tier, so $out is exactly an OCI artifact root and a later
  # `flux push artifact --path=result` needs no path surgery.
  perTier = lib.listToAttrs (
    map (
      { tree, name }:
      lib.nameValuePair "cue-render-${name}" (render {
        pname = "cue-render-${name}";
        name = "Rendered manifests for the ${name} tier";
        command = "render";
        instance = "./${tree}/${name}";
      })
    ) tiers
  );

  # The level-2 Kustomizations and OCIRepositories, which are committed to git
  # rather than shipped in an artifact.
  bootstrap = render {
    pname = "cue-render-bootstrap";
    name = "Rendered Flux bootstrap layer";
    command = "bootstrap";
    instance = "./clusters/nyx/flux";
  };
}
