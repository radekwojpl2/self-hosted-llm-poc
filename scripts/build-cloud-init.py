#!/usr/bin/env python3
"""Assembles cloud-init.yaml by injecting scripts as write_files entries."""
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
CLOUD_INIT = os.path.join(REPO_ROOT, 'cloud-init.yaml')
MARKER = '# SCRIPTS INJECTED HERE BY CI'

SCRIPTS = [
    ('setup-phase1.sh', '/usr/local/bin/setup-phase1.sh'),
    ('setup-phase2.sh', '/usr/local/bin/setup-phase2.sh'),
    ('deepseek-r1-32k-start', '/usr/local/bin/deepseek-r1-32k-start'),
    ('start', '/usr/local/bin/start'),
    ('attach-start', '/usr/local/bin/attach-start'),
]

def to_write_files_entry(vm_path, content):
    indented = '\n'.join('      ' + line for line in content.splitlines())
    return f"  - path: {vm_path}\n    permissions: '0755'\n    content: |\n{indented}"

with open(CLOUD_INIT, 'r') as f:
    template = f.read()

entries = []
for filename, vm_path in SCRIPTS:
    with open(os.path.join(SCRIPTS_DIR, filename), 'r') as f:
        entries.append(to_write_files_entry(vm_path, f.read()))

assembled = template.replace(MARKER, '\n'.join(entries))

with open(CLOUD_INIT, 'w') as f:
    f.write(assembled)

print(f"Assembled cloud-init.yaml with {len(SCRIPTS)} scripts injected.")
