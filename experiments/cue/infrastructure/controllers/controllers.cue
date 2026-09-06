package controllers

// cSpell:ignore certmanager redisoperator

import (
	"github.com/joker9944/k8s-config/schema"
	certmanager "github.com/joker9944/k8s-config/infrastructure/controllers/cert-manager:certmanager"
	"github.com/joker9944/k8s-config/infrastructure/controllers/cnpg"
	"github.com/joker9944/k8s-config/infrastructure/controllers/longhorn"
	"github.com/joker9944/k8s-config/infrastructure/controllers/metallb"
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
		"cert-manager":   certmanager.bundle
		"cnpg":           cnpg.bundle
		"longhorn":       longhorn.bundle
		"metallb":        metallb.bundle
		"redis-operator": redisoperator.bundle
		"reflector":      reflector.bundle
		"traefik":        traefik.bundle
		"volsync":        volsync.bundle
	}
}
