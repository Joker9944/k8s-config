{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:
buildGoModule (finalAttrs: {
  pname = "gomod-cap";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "gotify";
    repo = "plugin-api";
    rev = "v${finalAttrs.version}";
    sha256 = "sha256-g0QmuEl9NYGkCtVZeOzLZUSC2M9aOpHr+GbEFLfW9eI=";
  };

  vendorHash = "sha256-lH6df9sjB5ntuAet+DfJbn6zYjojxHgHzGhtDIttFgo=";

  meta = {
    description = "`gomod-cap` is a simple util to ensure that plugin `go.mod` files does not have higher version requirements than the main gotify `go.mod` file.";
    homepage = "https://github.com/gotify/plugin-api";
    license = lib.licenses.mit;
    mainProgram = "gomod-cap";
  };
})
