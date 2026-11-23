package manifests

import (
	"github.com/joker9944/k8s-config/schema"

	"github.com/joker9944/k8s-config/apps/audiobookshelf"
	"github.com/joker9944/k8s-config/apps/jellyfin"
	"github.com/joker9944/k8s-config/apps/jellyseerr"
	"github.com/joker9944/k8s-config/apps/komga"
	"github.com/joker9944/k8s-config/apps/opencloud"
	"github.com/joker9944/k8s-config/apps/qbittorrent"
	"github.com/joker9944/k8s-config/apps/servarr"
	"github.com/joker9944/k8s-config/apps/valheim"

	"github.com/joker9944/k8s-config/infrastructure/alloy"
	certmanager "github.com/joker9944/k8s-config/infrastructure/cert-manager:certmanager"
	certsconfig "github.com/joker9944/k8s-config/infrastructure/certs-config:certsconfig"
	"github.com/joker9944/k8s-config/infrastructure/cnpg"
	cnpgconfig "github.com/joker9944/k8s-config/infrastructure/cnpg-config:cnpgconfig"
	"github.com/joker9944/k8s-config/infrastructure/garage"
	genericdeviceplugin "github.com/joker9944/k8s-config/infrastructure/generic-device-plugin:genericdeviceplugin"
	"github.com/joker9944/k8s-config/infrastructure/gotify"
	"github.com/joker9944/k8s-config/infrastructure/grafana"
	"github.com/joker9944/k8s-config/infrastructure/headlamp"
	kanidmcluster "github.com/joker9944/k8s-config/infrastructure/kanidm-cluster:kanidmcluster"
	kanidmoperator "github.com/joker9944/k8s-config/infrastructure/kanidm-operator:kanidmoperator"
	kubeprometheusstack "github.com/joker9944/k8s-config/infrastructure/kube-prometheus-stack:kubeprometheusstack"
	"github.com/joker9944/k8s-config/infrastructure/loki"
	"github.com/joker9944/k8s-config/infrastructure/longhorn"
	longhornconfig "github.com/joker9944/k8s-config/infrastructure/longhorn-config:longhornconfig"
	nvidiadeviceplugin "github.com/joker9944/k8s-config/infrastructure/nvidia-device-plugin:nvidiadeviceplugin"
	redisoperator "github.com/joker9944/k8s-config/infrastructure/redis-operator:redisoperator"
	"github.com/joker9944/k8s-config/infrastructure/reflector"
	"github.com/joker9944/k8s-config/infrastructure/reloader"
	tailscaleconfig "github.com/joker9944/k8s-config/infrastructure/tailscale-config:tailscaleconfig"
	tailscaleoperator "github.com/joker9944/k8s-config/infrastructure/tailscale-operator:tailscaleoperator"
	"github.com/joker9944/k8s-config/infrastructure/traefik"
	"github.com/joker9944/k8s-config/infrastructure/volsync"
)

// Membership is these two lists: a workload is deployed because it is named
// here, and nowhere else. The tree is a folder convention, not a boundary —
// both land in the one artifact.
infrastructure: {
	"alloy":                 alloy.bundle
	"cert-manager":          certmanager.bundle
	"certs-config":          certsconfig.bundle
	"cnpg":                  cnpg.bundle
	"cnpg-config":           cnpgconfig.bundle
	"garage":                garage.bundle
	"generic-device-plugin": genericdeviceplugin.bundle
	"gotify":                gotify.bundle
	"grafana":               grafana.bundle
	"headlamp":              headlamp.bundle
	"kanidm-cluster":        kanidmcluster.bundle
	"kanidm-operator":       kanidmoperator.bundle
	"kube-prometheus-stack": kubeprometheusstack.bundle
	"loki":                  loki.bundle
	"longhorn":              longhorn.bundle
	"longhorn-config":       longhornconfig.bundle
	"nvidia-device-plugin":  nvidiadeviceplugin.bundle
	"redis-operator":        redisoperator.bundle
	"reflector":             reflector.bundle
	"reloader":              reloader.bundle
	"tailscale-config":      tailscaleconfig.bundle
	"tailscale-operator":    tailscaleoperator.bundle
	"traefik":               traefik.bundle
	"volsync":               volsync.bundle
}

apps: {
	"audiobookshelf": audiobookshelf.bundle
	"jellyfin":       jellyfin.bundle
	"jellyseerr":     jellyseerr.bundle
	"komga":          komga.bundle
	"opencloud":      opencloud.bundle
	"qbittorrent":    qbittorrent.bundle
	"servarr":        servarr.bundle
	"valheim":        valheim.bundle
}

manifests: schema.#Manifests & {
	name:    "nyx-manifests"
	bundles: infrastructure & apps
}
