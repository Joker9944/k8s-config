package controllers

// cSpell:ignore certmanager certsconfig cnpgconfig longhornconfig metallbconfig redisoperator

import (
	"github.com/joker9944/k8s-config/schema"
	certsconfig "github.com/joker9944/k8s-config/infrastructure/controllers/certs-config:certsconfig"
	certmanager "github.com/joker9944/k8s-config/infrastructure/controllers/cert-manager:certmanager"
	"github.com/joker9944/k8s-config/infrastructure/controllers/cnpg"
	cnpgconfig "github.com/joker9944/k8s-config/infrastructure/controllers/cnpg-config:cnpgconfig"
	"github.com/joker9944/k8s-config/infrastructure/controllers/longhorn"
	longhornconfig "github.com/joker9944/k8s-config/infrastructure/controllers/longhorn-config:longhornconfig"
	"github.com/joker9944/k8s-config/infrastructure/controllers/metallb"
	metallbconfig "github.com/joker9944/k8s-config/infrastructure/controllers/metallb-config:metallbconfig"
	redisoperator "github.com/joker9944/k8s-config/infrastructure/controllers/redis-operator:redisoperator"
	"github.com/joker9944/k8s-config/infrastructure/controllers/reflector"
	"github.com/joker9944/k8s-config/infrastructure/controllers/traefik"
	"github.com/joker9944/k8s-config/infrastructure/controllers/volsync"
)

// The controllers tier. Membership is this list: a workload is deployed here
// because it is named, which is what
// infrastructure/nyx/controllers/controllers-sync.yaml used to say.
tier: schema.#Tier & {
	bundles: {
		"cert-manager":    certmanager.bundle
		"certs-config":    certsconfig.bundle
		"cnpg":            cnpg.bundle
		"cnpg-config":     cnpgconfig.bundle
		"longhorn":        longhorn.bundle
		"longhorn-config": longhornconfig.bundle
		"metallb":         metallb.bundle
		"metallb-config":  metallbconfig.bundle
		"redis-operator":  redisoperator.bundle
		"reflector":       reflector.bundle
		"traefik":         traefik.bundle
		"volsync":         volsync.bundle
	}
}
