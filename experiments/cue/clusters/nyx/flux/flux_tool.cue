package flux

// Renders the bootstrap layer into <out>/clusters/nyx/flux/, which is what would
// be committed to git rather than pushed as an artifact:
//
//   app-sync.yaml             the apps tiers, one OCIRepository and one
//   infrastructure-sync.yaml  Kustomization each
//
// Run it with `cue cmd --inject out=<dir> bootstrap ./clusters/nyx/flux`.

import (
	"encoding/yaml"
	"tool/file"
)

_out: string @tag(out)

_root: "\(_out)/clusters/nyx/flux"

// The file each tree lands in, keeping the two names the cluster already
// reconciles.
_files: {
	apps:           "app-sync.yaml"
	infrastructure: "infrastructure-sync.yaml"
}

command: bootstrap: {
	mkdir: file.Mkdir & {
		path:          _root
		createParents: true
	}

	for tree, docs in sync {
		"write-\(tree)": file.Create & {
			$after:   command.bootstrap.mkdir
			filename: "\(_root)/\(_files[tree])"
			contents: yaml.MarshalStream(docs)
		}
	}
}
