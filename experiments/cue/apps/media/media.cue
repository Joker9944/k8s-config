package media

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/apps/media/jellyfin"
	"github.com/joker9944/k8s-config/apps/media/servarr"
)

// The media tier. Membership is this list: a workload is deployed here because
// it is named, which is what apps/nyx/media/media-sync.yaml used to say.
tier: schema.#Tier & {
	bundles: {
		"jellyfin": jellyfin.bundle
		"servarr":  servarr.bundle
	}
}
