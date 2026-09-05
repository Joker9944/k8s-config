package nyx

import "encoding/yaml"

manifests: yaml.MarshalStream(jellyfin.out)

servarrManifests: yaml.MarshalStream(servarr.out)
