#!/usr/bin/env python3
"""Execute only base policy; read proposed manifests and diffs as Git data."""
import argparse
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def check(base, head, mode):
    repository = Path(git('.', 'rev-parse', '--show-toplevel').decode().strip())
    # Resolve before constructing revision:path arguments; invalid refs fail closed.
    base = git(repository, 'rev-parse', '--verify', f'{base}^{{commit}}').decode().strip()
    head = git(repository, 'rev-parse', '--verify', f'{head}^{{commit}}').decode().strip()
    with tempfile.TemporaryDirectory(prefix='clara-policy-') as directory:
        trusted = Path(directory) / 'trusted'
        proposal = Path(directory) / 'proposal'
        # No checkout, filters, build steps, hooks or imports from the proposal.
        subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout',
                        str(repository), str(proposal)], check=True)
        git(proposal, 'update-ref', 'HEAD', head)
        git(proposal, 'read-tree', head)
        paths = git(repository, 'ls-tree', '-rz', '--name-only', base).decode().split('\0')
        for path in paths:
            if (path.startswith('scripts/guardrails/') and path.endswith('.py')) or (
                    path.startswith('guardrails/') and path.endswith('.txt')):
                destination = trusted / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(git(repository, 'show', f'{base}:{path}'))
                if path.startswith('guardrails/'):
                    rules = proposal / path
                    rules.parent.mkdir(parents=True, exist_ok=True)
                    rules.write_bytes(destination.read_bytes())
        for path in git(repository, 'ls-tree', '-rz', '--name-only', head).decode().split('\0'):
            if Path(path).name in ('Package.swift', 'Gemfile'):
                entry = git(repository, 'ls-tree', head, '--', path).decode()
                if not entry.startswith(('100644 blob ', '100755 blob ')):
                    raise ValueError(f'Manifest must be a regular file: {path}')
                destination = proposal / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(git(repository, 'show', f'{head}:{path}'))
        policy_path = trusted / 'scripts/guardrails/policy_check.py'
        sys.path.insert(0, str(policy_path.parent))
        spec = importlib.util.spec_from_file_location('trusted_policy_check', policy_path)
        policy = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = policy
        spec.loader.exec_module(policy)
        policy.ROOT = proposal
        sys.argv = [str(policy_path), '--mode', mode, '--base', base]
        return policy.main()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--mode', choices=['pr', 'push'], default='pr')
    args = parser.parse_args()
    sys.exit(check(args.base, args.head, args.mode))
