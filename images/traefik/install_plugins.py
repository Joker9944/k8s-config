#!/usr/bin/python3
import os

from git import Repo

PLUGIN_INDICATOR_PREFIX = 'PLUGIN_'
PLUGIN_METHOD_SUFFIX = '_METHOD'
PLUGIN_REPO_SUFFIX = '_REPO'
PLUGIN_VERSION_SUFFIX = '_VERSION'


def main():
	plugins = plugin_list()
	clone_plugins(plugins)


def plugin_list() -> dict[str, dict[str, str]]:
	plugins = {}
	for env, value in os.environ.items():
		if not env.startswith(PLUGIN_INDICATOR_PREFIX):
			continue
		name = (
			env.removeprefix(PLUGIN_INDICATOR_PREFIX)
			.removesuffix(PLUGIN_METHOD_SUFFIX)
			.removesuffix(PLUGIN_REPO_SUFFIX)
			.removesuffix(PLUGIN_VERSION_SUFFIX)
		)
		if name not in plugins:
			plugins[name] = {}
		if env.endswith(PLUGIN_METHOD_SUFFIX):
			plugins[name][PLUGIN_METHOD_SUFFIX] = value
		elif env.endswith(PLUGIN_REPO_SUFFIX):
			plugins[name][PLUGIN_REPO_SUFFIX] = value
		elif env.endswith(PLUGIN_VERSION_SUFFIX):
			plugins[name][PLUGIN_VERSION_SUFFIX] = value
		else:
			raise RuntimeError(f'Invalid plugin env variable: {env}={value}')
	return plugins


def clone_plugins(plugins: dict[str, dict[str, str]]) -> None:
	for name, info in plugins.items():
		Repo.clone_from(
			url=info[PLUGIN_METHOD_SUFFIX] + '://' + info[PLUGIN_REPO_SUFFIX],
			to_path='/plugins-local/src/' + info[PLUGIN_REPO_SUFFIX],
			branch=info[PLUGIN_VERSION_SUFFIX]
		)


if __name__ == "__main__":
	main()
