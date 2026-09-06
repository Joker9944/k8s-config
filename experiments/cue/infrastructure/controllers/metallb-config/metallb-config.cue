package metallbconfig

// cSpell:ignore metallbconfig

import "github.com/joker9944/k8s-config/schema"

bundle: schema.#ConfigBundle & {
	source: "infrastructure/nyx/config/metallb"
	resources: [_pool, _advertisement]
}

// The namespace MetalLB itself runs in; these two resources are only read by its
// controller, which watches its own namespace.
let ns = "metallb-system"

// The upper half of the LAN, handed out to LoadBalancer services. Traefik pins
// the first address of the range.
_pool: {
	apiVersion: "metallb.io/v1beta1"
	kind:       "IPAddressPool"
	metadata: {name: "internal", namespace: ns}
	spec: addresses: ["192.168.0.128/25"]
}

// L2 rather than BGP, advertised on both physical interfaces.
_advertisement: {
	apiVersion: "metallb.io/v1beta1"
	kind:       "L2Advertisement"
	metadata: {name: "internal", namespace: ns}
	spec: {
		ipAddressPools: [_pool.metadata.name]
		interfaces: ["enp2s0", "enp5s0"]
	}
}
