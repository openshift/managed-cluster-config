#!/usr/bin/env python

import logging
import os
import re
import sys
from abc import (
     ABC,
     abstractmethod,
)
from argparse import ArgumentParser
from collections import defaultdict
from pathlib import Path

import oyaml as yaml


_DEFAULT_DIR=Path('.', 'deploy', 'backplane')


_DEFAULT_RULES=[
     'cluster-role-suffix',
     'no-wildcards',
     'subject-permission-role-names',
     'subject-permission-deny-cluster-admin',
]


class _BackplaneRuleException(Exception):
     pass


class _Rule(ABC):
     def __init__(self, name, logger):
          self.name = name
          self.logger = logger

     @abstractmethod
     def run(self, registry):
          pass

     def log_failure(self, file, message):
          self.logger.error(f'{self.name}: {file}: {message}')


class _ClusterRoleSuffixRule(_Rule):
     def __init__(self, logger):
          super().__init__('cluster-role-suffix', logger)

     def run(self, registry):
          failed = False

          for path, cluster_role in registry.get_resources_of_type('ClusterRole').items():
               name = cluster_role.content['metadata']['name']

               if not self._has_valid_name_suffix(name):
                    failed = True

                    self.log_failure(
                         path,
                         f"ClusterRole '{name}' is not suffixed with '-cluster' or '-project'"),

               if not self._file_suffix_matches_name_suffix(path, name):
                    failed = True

                    self.log_failure(
                         path,
                         f"ClusterRole '{name}' has suffix different than its containing file"
                    )

          return failed

     @staticmethod
     def _has_valid_name_suffix(name):
          valid_suffixes = ('-project', '-cluster')

          return any(name.endswith(s) for s in valid_suffixes)

     @staticmethod
     def _file_suffix_matches_name_suffix(path, name):
          return path.stem.split('.', 1)[0].rsplit('-', 1)[-1] == name.rsplit('-', 1)[-1]


class _NoWildcardsRule(_Rule):
     def __init__(self, logger):
          super().__init__('no-wildcards', logger)

     def run(self, registry):
          failed = False

          for path, role in registry.get_resources_of_type('Role').items():
               name = role.content['metadata']['name']

               if self._has_invalid_rules(role):
                    failed = True

                    self.log_failure(
                         path,
                         f"Role '{name}' has rules(s) which contain the wildcard '*'"
                    )

          for path, cluster_role in registry.get_resources_of_type('ClusterRole').items():
               name = cluster_role.content['metadata']['name']

               if self._has_invalid_rules(cluster_role):
                    failed = True

                    self.log_failure(
                         path,
                         f"ClusterRole '{name}' has rules(s) which contain the wildcard '*'"
                    )

          return failed

     @staticmethod
     def _has_invalid_rules(role_like):
          for rule in role_like.content.get('rules', []):
               apiGroups = rule['apiGroups']
               resources = rule['resources']
               verbs = rule['verbs']

               if '*' in apiGroups + resources + verbs:
                    return True

          return False


class _SubjectPermissionRoleNamesRule(_Rule):
     def __init__(self, logger):
          super().__init__('subject-permission-role-names', logger)

     def run(self, registry):
          failed = False

          for path, subject_permission in registry.get_resources_of_type('SubjectPermission').items():
               name = subject_permission.content['metadata']['name']

               if invalid_perms := self._invalid_cluster_permission_names(subject_permission):
                    failed = True

                    self.log_failure(
                         path,
                         f"SubjectPermission '{name}' has clusterPermission(s) '{', '.join(invalid_perms)}'"
                         " without the '-cluster' suffix"
                    )

               if invalid_perms := self._invalid_permission_names(subject_permission):
                    failed = True

                    self.log_failure(
                         path,
                         f"SubjectPermission '{name}' has permission(s) '{', '.join(invalid_perms)}'"
                         " without the '-project' suffix"
                    )

          return failed

     def _invalid_cluster_permission_names(self, subject_permission):
          cluster_permissions = subject_permission.content['spec'].get('clusterPermissions', [])
          unknown_role_names = self._filter_known_roles(cluster_permissions)

          return [n for n in unknown_role_names if not n.endswith('-cluster')]

     def _invalid_permission_names(self, subject_permission):
          permissions = subject_permission.content['spec'].get('permissions', [])
          role_names = [name for p in permissions if (name := p.get('clusterRoleName')) ]
          unknown_role_names = self._filter_known_roles(role_names)

          return [n for n in unknown_role_names if not n.endswith('-project')]

     @staticmethod
     def _filter_known_roles(role_names):
          known_roles = ('admin', 'dedicated-readers', 'view')

          return [n for n in role_names if not n in known_roles]


_CLUSTER_ADMIN_NAMESPACE = 'openshift-backplane-cluster-admin'


class _SubjectPermissionDenyClusterAdminRule(_Rule):
     def __init__(self, logger):
          super().__init__('subject-permission-deny-cluster-admin', logger)

     def run(self, registry):
          failed = False

          for path, subject_permission in registry.get_resources_of_type('SubjectPermission').items():
               name = subject_permission.content['metadata']['name']

               if invalid_permissions := self._invalid_permissions(subject_permission):
                    failed = True

                    self.log_failure(
                         path,
                         f"SubjectPermission '{name}' has permission(s) which do not"
                         f" explicitly deny clusterRole(s) '{', '.join(invalid_permissions)}'"
                         f" access to '{_CLUSTER_ADMIN_NAMESPACE}'"
                    )

          return failed

     @staticmethod
     def _invalid_permissions(subject_permission):
          permissions = subject_permission.content['spec'].get('permissions', [])

          invalid = []

          for perm in permissions:
               denied_re = perm.get('namespacesDeniedRegex')
               if denied_re and re.match(denied_re, _CLUSTER_ADMIN_NAMESPACE):
                    continue

               invalid.append(perm['clusterRoleName'])

          return invalid

class _Config:
     def __init__(self, logger=None, dir="", rules=None):
          self.logger = logger or logging.getLogger(__name__)
          self.dir = dir
          self.rules = rules

     @classmethod
     def from_args(cls):
          parser = ArgumentParser()
          parser.add_argument('--directory', type=Path, default=_DEFAULT_DIR)
          parser.add_argument('--rules', nargs='*', default=_DEFAULT_RULES)

          args = parser.parse_args()

          try:
               rules = [_NAME_TO_RULE[n] for n in args.rules]
          except KeyError as e:
               raise _BackplaneRuleException(f'unknown rule provided: {e}')

          return cls(
               dir=args.directory,
               rules=rules,
          )


_NAME_TO_RULE = {
     'cluster-role-suffix': _ClusterRoleSuffixRule,
     'no-wildcards': _NoWildcardsRule,
     'subject-permission-role-names': _SubjectPermissionRoleNamesRule,
     'subject-permission-deny-cluster-admin': _SubjectPermissionDenyClusterAdminRule,
}


class _RuleRunner:
     def __init__(self, logger, registry, rules):
          self._logger = logger
          self._registry = registry
          self._rules = rules

     @classmethod
     def from_config(cls, config):
          return cls(
               logger=config.logger,
               registry=_ResourceRegistry.from_config(config),
               rules=config.rules,
          )

     def run_rules(self):
          # pre-computing to avoid short-circuiting behavior of 'any'
          results = [rule(self._logger).run(self._registry) for rule in self._rules]

          return any(results)


class _ResourceRegistry:
     def __init__(self, entry_map, config_map):
          self._entry_map = entry_map
          self._config_map = config_map

     @classmethod
     def from_config(cls, config):
          all_configs = {}
          all_k8s_resources = defaultdict(dict)

          for root, _, ents in os.walk(config.dir):
               yamls = {
                    p: _load_yaml_from_file(p)
                    for p in [Path(root, e) for e in ents]
                    if _is_yaml(p)
               }

               configs = {p: y for (p, y) in yamls.items() if _is_config(y)}

               config_ref = None

               if len(configs) > 1:
                    raise _BackplaneRuleException(f"multiple 'config.yaml' files exist in directory '{root}'")
               elif len(configs) > 0:
                    config_ref = list(configs.keys())[0]

               all_configs.update(configs)

               k8s_resources = {
                    p: _ResourceEntry(y, config_ref)
                    for (p, y) in yamls.items()
                    if _is_k8s_resource(y)
               }

               for path, resource in k8s_resources.items():
                    all_k8s_resources[resource.content['kind']][path] = resource

          return cls(
               entry_map=all_k8s_resources,
               config_map=all_configs,
          )

     def get_resources_of_type(self, type):
          return self._entry_map[type]


def _load_yaml_from_file(path):
     with path.open() as f:
          return yaml.safe_load(f)


def _is_yaml(path):
     return path.suffix in ('.yml', '.yaml')


def _is_k8s_resource(yaml_dict):
     return "kind" in yaml_dict


def _is_config(yaml_dict):
     return "deploymentMode" in yaml_dict


class _ResourceEntry:
     def __init__(self, content, config_ref):
          self.content = content
          self.config_ref = config_ref


def main():
     try:
          registry = _RuleRunner.from_config(_Config.from_args())

          failed = registry.run_rules()
     except _BackplaneRuleException as e:
          print(f'Unexpected error occurred: {e}')

          sys.exit(1)

     if failed:
          print('Backplane Rules: FAILED')

          sys.exit(1)

     print('Backplane Rules: PASSED')


if __name__ == '__main__':
     main()
