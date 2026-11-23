package flux

// Renders the bootstrap layer into <out>/clusters/nyx/flux/, which is committed
// to git rather than pushed as an artifact:
//
//   nyx-manifests-sync.yaml  the OCIRepository and the level-2 Kustomization
//
// Run it with `cue cmd --inject out=<dir> bootstrap ./clusters/nyx/flux`.

import (
	"encoding/yaml"
	"tool/file"
)

_out: string @tag(out)

_root: "\(_out)/clusters/nyx/flux"

command: bootstrap: {
	mkdir: file.Mkdir & {
		path:          _root
		createParents: true
	}

	write: file.Create & {
		$after:   command.bootstrap.mkdir
		filename: "\(_root)/\(_name)-sync.yaml"
		contents: yaml.MarshalStream(sync)
	}
}
