#!/usr/bin/env python3
"""Data-only decoder profile CLI over Neovim's local RPC socket (no Python deps)."""
import argparse
import json
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--server', required=True)
parser.add_argument('--nvim', default='nvim')
sub = parser.add_subparsers(dest='action', required=True)
sub.add_parser('use').add_argument('name')
sub.add_parser('register').add_argument('file')
args = parser.parse_args()
if args.action == 'use':
    code = 'require("dap-view.decoders").use(_A)'
    argument = args.name
else:
    code = 'require("dap-view.decoders").register_decoder_profile(vim.json.decode(_A))'
    with open(args.file, encoding='utf-8') as source:
        argument = json.dumps(json.load(source))
# JSON string syntax is compatible with Vim's double-quoted strings here.
# User data is the luaeval argument, never part of the Lua source or a shell command.
expr = f"luaeval('{code}', {json.dumps(argument, ensure_ascii=True)})"
raise SystemExit(subprocess.run([args.nvim, '--server', args.server, '--remote-expr', expr]).returncode)
