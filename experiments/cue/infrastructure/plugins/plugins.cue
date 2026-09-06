package plugins

// cSpell:ignore genericdeviceplugin nvidiadeviceplugin

import (
	"github.com/joker9944/k8s-config/schema"
	genericdeviceplugin "github.com/joker9944/k8s-config/infrastructure/plugins/generic-device-plugin:genericdeviceplugin"
	nvidiadeviceplugin "github.com/joker9944/k8s-config/infrastructure/plugins/nvidia-device-plugin:nvidiadeviceplugin"
)

// The plugins tier. Membership is this list: a workload is deployed here because
// it is named, which is what infrastructure/nyx/plugins/plugin-sync.yaml used to
// say.
tier: schema.#Tier & {
	bundles: {
		"generic-device-plugin": genericdeviceplugin.bundle
		"nvidia-device-plugin":  nvidiadeviceplugin.bundle
	}
}
