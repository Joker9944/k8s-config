package nyx

// Ciphertext never passes through CUE evaluation — it is injected at render
// time from the SOPS file on disk. See workflows/secrets-sops.md.
secretData: string @tag(secretdata)
