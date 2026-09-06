package tier

// cSpell:ignore dedicatedserverabioticfactor dsaf

import (
	"github.com/joker9944/k8s-config/schema"
	"github.com/joker9944/k8s-config/apps/media/audiobookshelf"
	dsaf "github.com/joker9944/k8s-config/apps/media/dedicated-server-abiotic-factor:dedicatedserverabioticfactor"
	"github.com/joker9944/k8s-config/apps/media/jellyfin"
	"github.com/joker9944/k8s-config/apps/media/jellyseerr"
	"github.com/joker9944/k8s-config/apps/media/komga"
	"github.com/joker9944/k8s-config/apps/media/openaudible"
	"github.com/joker9944/k8s-config/apps/media/qbittorrent"
	"github.com/joker9944/k8s-config/apps/media/servarr"
)

// The media tier. Membership is this list: a workload is deployed here because
// it is named, which is what apps/nyx/media/media-sync.yaml used to say.
tier: schema.#Tier & {
	tree: "apps"
	name: "media"

	bundles: {
		"audiobookshelf":                  audiobookshelf.bundle
		"dedicated-server-abiotic-factor": dsaf.bundle
		"jellyfin":                        jellyfin.bundle
		"jellyseerr":                      jellyseerr.bundle
		"komga":                           komga.bundle
		"openaudible":                     openaudible.bundle
		"qbittorrent":                     qbittorrent.bundle
		"servarr":                         servarr.bundle
	}
}
