{
  lib,
  python3Packages,
  fetchFromGitHub,
  ...
}:
python3Packages.buildPythonApplication (finalAttrs: {
  pname = "sops-pre-commit";
  version = "2.1.1";

  src = fetchFromGitHub {
    owner = "onedr0p"; # cSpell:ignore onedr0p
    repo = finalAttrs.pname;
    rev = "v${finalAttrs.version}";
    sha256 = "sha256-bzPCm8PxWE0ymEaBawnMp937oa9g3W69yTi/s5Srycc=";
  };

  pyproject = true;
  build-system = with python3Packages; [ setuptools ];

  meta = {
    description = "Sops pre-commit hook";
    homepage = "https://github.com/onedr0p/sops-pre-commit";
    license = lib.licenses.mit;
    mainProgram = "forbid_secrets";
  };
})
