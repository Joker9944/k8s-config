{
  writeShellApplication,
  coreutils,
  cue,
  gawk,
  ...
}:
writeShellApplication {
  name = "capability-graph";
  runtimeInputs = [
    coreutils
    cue
    gawk
  ];
  text = ''
    doc=.okf/architecture/capability-graph.md
    gen=$(mktemp)
    out=$(mktemp)
    trap 'rm -f "$gen" "$out"' EXIT
    (cd cue && cue export ./graph -e doc --out text) >"$gen"
    awk -v gen="$gen" '
      /<!-- capability-graph:end -->/ { skip = 0 }
      !skip { print }
      /<!-- capability-graph:begin -->/ {
        print ""
        while ((getline line < gen) > 0) print line
        skip = 1
      }
    ' "$doc" >"$out"
    cat "$out" >"$doc"
  '';
  meta.description = "Splice the generated capability graph into its OKF concept";
}
