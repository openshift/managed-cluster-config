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


_DEFAULT_DIR = Path('.', 'deploy', 'backplane')


_DEFAULT_RULES = [
    'cluster-role-suffix',
    'no-wildcards',
    'subject-permission-role-names',
    'subject-permission-deny-cluster-admin',
]


class _BackplaneRuleException(Exception):
    pass


class _Rule(ABC):
    """Rule applied to enforce proper usage of backplane
    resources and the access they provide.
    """

    def __init__(self, name, logger):
        self.name = name
        self.logger = logger

    @abstractmethod
    def run(self, registry):
        """Runs the rule against a given registry of resources
        and returns 'True' if the rule fails. Any rule
        violations should be reported by using the 'log_failure'
        method of this class.

        :param registry: _ResourceRegistry containing resources
            to be tested
        :type registry: _ResourceRegistry
        """

    def log_failure(self, file, message):
        self.logger.error(f'{self.name}: {file}: {message}')


class _ClusterRoleSuffixRule(_Rule):
    """Ensures ClusterRole names are properly suffixed
    and that the files containing them have matching
    suffixes.
    """

    _VALID_SUFFIXES = (
        '-aggregate',
        '-project',
        '-cluster',
        'backplane-impersonate-cluster-admin',
    )

    def __init__(self, logger):
        super().__init__('cluster-role-suffix', logger)

    def run(self, registry):
        failed = False

        for path, cluster_role in registry.get_resources_of_type('ClusterRole').items():
            if not self._has_valid_name_suffix(cluster_role.name):
                failed = True

                self.log_failure(
                    path,
                    f"ClusterRole '{cluster_role.name}' is not suffixed with"
                    f" one of '{', '.join(self._VALID_SUFFIXES)}'"
                )

            if not self._file_suffix_matches_name_suffix(path, cluster_role.name):
                failed = True

                self.log_failure(
                    path,
                    f"ClusterRole '{cluster_role.name}' has suffix different"
                    " from its containing file"
                )

        return failed

    def _has_valid_name_suffix(self, name):
        return any(name.endswith(s) for s in self._VALID_SUFFIXES)

    @staticmethod
    def _file_suffix_matches_name_suffix(path, name):
        # a-<suffix>.b.c
        path_suffix = path.stem.split('.', 1)[0].rsplit('-', 1)[-1]

        # a-b-<suffix>
        name_suffix = name.rsplit('-', 1)[-1]

        return path_suffix == name_suffix


class _NoWildcardsRule(_Rule):
    """Enforces the usage restrictions on wildcards '*'
    in RBAC rules for Roles and ClusterRoles.
    """

    def __init__(self, logger):
        super().__init__('no-wildcards', logger)

    def run(self, registry):
        failed = False

        roles = (
            registry.get_resources_of_type('Role').items() |
            registry.get_resources_of_type('ClusterRole').items()
        )

        for path, role in roles:
            if self._has_invalid_api_groups(role):
                failed = True

                self.log_failure(
                    path,
                    f"{role.kind} '{role.name}' has apiGroups which contain wildcard '*'"
                )

            if self._has_invalid_resources(role):
                failed = True

                self.log_failure(
                    path,
                    f"{role.kind} '{role.name}' has resources which contain the wildcard '*'"
                    " for either \"\" apiGroups or with verbs delete / deletecollection"
                )

            if self._has_invalid_verbs(role):
                failed = True

                self.log_failure(
                    path,
                    f"{role.kind} '{role.name}' has verbs which contain the wildcard '*'"
                )

        return failed

    @staticmethod
    def _has_invalid_api_groups(role_like):
        rules = role_like.content.get('rules', [])

        return any('*' in r.get('apiGroups', []) for r in rules)

    def _has_invalid_resources(self, role_like):
        for rule in role_like.content.get('rules', []):
            if not all(f in rule for f in ('apiGroups', 'resources', 'verbs')):
                continue

            api_groups = rule['apiGroups']
            resources = rule['resources']
            verbs = rule['verbs']

            has_wildcard = False
            if '*' in resources:
                has_wildcard = True

            # cannot have '*' resource with "" apiGroup since it includes Secrets
            if has_wildcard and "" in api_groups:
                return True

            # cannot have '*' resource for delete or deletecollection
            has_bad_verbs = (
                {x.lower() for x in verbs} &
                {'delete', 'deletecollection', '*'}
            )

            if all([
                has_wildcard,
                not self._is_allowed_api_groups(api_groups),
                has_bad_verbs,
            ]):
                return True

        return False

    def _has_invalid_verbs(self, role_like):
        for rule in role_like.content.get('rules', []):
            if not all(f in rule for f in ('apiGroups', 'verbs')):
                continue

            api_groups = rule['apiGroups']
            verbs = rule['verbs']

            if '*' in verbs and not self._is_allowed_api_groups(api_groups):
                return True

        return False

    @staticmethod
    def _is_allowed_api_groups(api_groups):
        # specific apiGroups we permit any verbs against
        allowed_api_groups = (
            'tekton.dev',
            'logging.openshift.io',
            'velero.io',
        )

        return all(g in allowed_api_groups for g in api_groups)


class _SubjectPermissionRoleNamesRule(_Rule):
    """Enforces that proper role names are used
    with SubjectPermissions based on whether they
    are cluster or namespace scoped.
    """

    def __init__(self, logger):
        super().__init__('subject-permission-role-names', logger)

    def run(self, registry):
        failed = False

        subject_permissions = registry.get_resources_of_type(
            'SubjectPermission').items()

        for path, subject_permission in subject_permissions:
            if invalid_perms := self._invalid_cluster_permission_names(subject_permission):
                failed = True

                self.log_failure(
                    path,
                    f"SubjectPermission '{subject_permission.name}' has clusterPermission(s)"
                    f"'{', '.join(invalid_perms)}' without the '-cluster' suffix"
                )

            if invalid_perms := self._invalid_permission_names(subject_permission):
                failed = True

                self.log_failure(
                    path,
                    f"SubjectPermission '{subject_permission.name}' has permission(s)"
                    f" '{', '.join(invalid_perms)}' without the '-project' suffix"
                )

        return failed

    def _invalid_cluster_permission_names(self, subject_permission):
        spec = subject_permission.content['spec']
        cluster_permissions = spec.get('clusterPermissions', [])
        unknown_role_names = self._filter_known_roles(cluster_permissions)

        return [n for n in unknown_role_names if not n.endswith('-cluster')]

    def _invalid_permission_names(self, subject_permission):
        spec = subject_permission.content['spec']
        permissions = spec.get('permissions', [])
        unknown_role_names = self._filter_known_roles(
            name for p in permissions if (name := p.get('clusterRoleName'))
        )

        return [n for n in unknown_role_names if not n.endswith('-project')]

    @staticmethod
    def _filter_known_roles(role_names):
        known_roles = (
            'admin',
            'dedicated-readers',
            'view',
            'system:openshift:cloud-credential-operator:cluster-reader',
        )

        return [n for n in role_names if n not in known_roles]


_CLUSTER_ADMIN_NAMESPACE = 'openshift-backplane-cluster-admin'


class _SubjectPermissionDenyClusterAdminRule(_Rule):
    """Enforces all SubjectPermissions to explicitly deny
    privileges to the cluster-admin namespace.
    """

    def __init__(self, logger):
        super().__init__('subject-permission-deny-cluster-admin', logger)

    def run(self, registry):
        failed = False

        for path, subject_permission in registry.get_resources_of_type('SubjectPermission').items():
            if invalid_permissions := self._invalid_permissions(subject_permission):
                failed = True

                self.log_failure(
                    path,
                    f"SubjectPermission '{subject_permission.name}' has permission(s) which do not"
                    f" explicitly deny clusterRole(s) '{', '.join(invalid_permissions)}'"
                    f" access to '{_CLUSTER_ADMIN_NAMESPACE}'"
                )

        return failed

    def _invalid_permissions(self, subject_permission):
        permissions = subject_permission.content['spec'].get('permissions', [])

        return [
            p['clusterRoleName']
            for p in permissions
            if not self._denies_cluster_admin_namespace(p)
        ]

    @staticmethod
    def _denies_cluster_admin_namespace(permission):
        denied_re = permission.get('namespacesDeniedRegex')

        return denied_re and re.match(denied_re, _CLUSTER_ADMIN_NAMESPACE)


class _Config:
    def __init__(self, logger=None, directory="", rules=None):
        self.logger = logger or logging.getLogger(__name__)
        self.dir = directory
        self.rules = rules

    @classmethod
    def from_args(cls):
        parser = ArgumentParser()
        parser.add_argument(
            '--directory',
            type=Path, default=_DEFAULT_DIR,
            help='Root directory to descend into when searching for resources',
        )
        parser.add_argument(
            '--rules',
            nargs='*', default=_DEFAULT_RULES,
            help=f"List of rules to enforce. Available Rules: {', '.join(_NAME_TO_RULE.keys())}",
        )

        args = parser.parse_args()

        try:
            rules = [_NAME_TO_RULE[n] for n in args.rules]
        except KeyError as exc:
            raise _BackplaneRuleException('unknown rule provided') from exc

        return cls(
            directory=args.directory,
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
        """Run rules against the supplied registry.

        :return: 'True' when any rules have failed.
        :rtype: bool
        """
        # pre-computing to avoid short-circuiting behavior of 'any'
        results = [
            rule(self._logger).run(self._registry) for rule in self._rules
        ]

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

            if len(configs) > 1:
                raise _BackplaneRuleException(
                    f"multiple 'config.yaml' files exist in directory '{root}'"
                )

            config_ref = None

            if len(configs) > 0:
                config_ref = list(configs.keys())[0]

            all_configs.update(configs)

            k8s_resources = {
                p: _ResourceEntry(y, config_ref)
                for (p, y) in yamls.items()
                if _is_k8s_resource(y)
            }

            for path, resource in k8s_resources.items():
                all_k8s_resources[resource.kind][path] = resource

        return cls(
            entry_map=all_k8s_resources,
            config_map=all_configs,
        )

    def get_resources_of_type(self, resource_type):
        return self._entry_map[resource_type]


def _load_yaml_from_file(path):
    with path.open() as file:
        return yaml.safe_load(file)


def _is_yaml(path):
    return path.suffix in ('.yml', '.yaml')


def _is_k8s_resource(yaml_dict):
    return 'kind' in yaml_dict


def _is_config(yaml_dict):
    return 'deploymentMode' in yaml_dict


class _ResourceEntry:
    def __init__(self, content, config_ref):
        self.content = content
        self.config_ref = config_ref

    @property
    def kind(self):
        return self.content['kind']

    @property
    def name(self):
        return self.content['metadata']['name']


def main():
    try:
        registry = _RuleRunner.from_config(_Config.from_args())

        failed = registry.run_rules()
    except _BackplaneRuleException as exc:
        print(f'Unexpected error occurred: {exc}')

        sys.exit(1)

    if failed:
        print('Backplane Rules: FAILED')

        sys.exit(1)

    print('Backplane Rules: PASSED')


if __name__ == '__main__':
    main()
