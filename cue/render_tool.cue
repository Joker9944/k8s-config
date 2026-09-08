package tier

// Renders one tier into a directory Flux can reconcile:
//
//   <out>/<tree>/<tier>/
//     sync/<tier>-sync.yaml    the level-3 Kustomizations
//     <bundle>/manifests.yaml  everything the bundle declares
//     <bundle>/*.secret.yaml   copied byte for byte, never evaluated
//
// Run it with `cue cmd --inject out=<dir> render ./<tree>/<tier>`. Every task is
// produced by a comprehension over the tier's own bundles, so adding a workload
// adds its files with nothing here to edit.

import (
	"encoding/yaml"
	"path"
	"tool/file"
)

_out: string @tag(out)

_root: "\(_out)/\(tier.tree)/\(tier.name)"

command: render: {
	// The sync directory sits beside the bundles rather than above them, because
	// kustomize-controller's generated kustomization walks subdirectories: with
	// the sync file at the artifact root, the level-2 Kustomization would apply
	// every bundle a second time and without decryption.
	"mkdir-sync": file.Mkdir & {
		path:          "\(_root)/sync"
		createParents: true
	}

	"sync": file.Create & {
		$after:   command.render["mkdir-sync"]
		filename: "\(_root)/sync/\(tier.name)-sync.yaml"
		contents: yaml.MarshalStream(tier.sync)
	}

	for name, _ in tier.bundles {
		"mkdir-\(name)": file.Mkdir & {
			path:          "\(_root)/\(name)"
			createParents: true
		}
	}

	for name, doc in tier.rendered {
		"manifests-\(name)": file.Create & {
			$after:   command.render["mkdir-\(name)"]
			filename: "\(_root)/\(name)/manifests.yaml"
			contents: doc
		}
	}

	// Passthrough, not evaluation: the ciphertext is read at command time and
	// written back unchanged. @embed would put it in a .cue file instead, which
	// is the shape forbid_secrets rejects.
	for name, paths in tier.secretFiles for src in paths {
		"read-\(src)": file.Read & {
			filename: src
			contents: bytes
		}
		// keyed by bundle and basename rather than by source path: two files
		// landing on one name in the same bundle collide here, loudly, instead of
		// overwriting each other
		"copy-\(name)-\(path.Base(src, "unix"))": file.Create & {
			$after:   command.render["mkdir-\(name)"]
			filename: "\(_root)/\(name)/\(path.Base(src, "unix"))"
			contents: command.render["read-\(src)"].contents
		}
	}
}
