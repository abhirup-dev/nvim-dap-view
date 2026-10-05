#!/usr/bin/env python3
"""Exercise the shipped CLI against an isolated actual Neovim RPC server."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[2]
nvim = os.environ.get('NVIM', 'nvim')
with tempfile.TemporaryDirectory(prefix='decoder-rpc-', dir='/tmp') as temp:
    socket = str(Path(temp) / 'nvim.sock')
    with open(Path(temp) / 'nvim.log', 'w+') as log:
        process = subprocess.Popen([nvim, '--headless', '--listen', socket, '-u',
                                    str(root / 'examples/decoders/init.lua')], cwd=root,
                                   stdout=log, stderr=log)
        try:
            for _ in range(100):
                if Path(socket).exists():
                    break
                time.sleep(.05)
            assert Path(socket).exists(), 'Neovim socket missing'
            base = ['python3', str(root / 'examples/decoders/profile.py'), '--nvim', nvim, '--server', socket]
            def cli(*args):
                return subprocess.run(base + list(args), capture_output=True, text=True, timeout=10)
            result = cli('register', str(root / 'examples/decoders/profile.json'))
            assert result.returncode == 0, result.stderr
            result = cli('use', 'rpc-protobuf')
            assert result.returncode == 0, result.stderr
            result = cli('use', 'off')
            assert result.returncode == 0, result.stderr
            bad = Path(temp) / 'bad.json'
            bad.write_text(json.dumps({'name':'bad', 'decoders':[{'name':'bad','kind':'command',
                'match':{'name':'x'},'command':'person','argv':['/bin/sh'],'source':{'kind':'value'}}]}))
            result = cli('register', str(bad))
            assert result.returncode != 0, 'runtime argv was accepted'
            result = cli('use', "'; vim.cmd('cq!'); --")
            assert result.returncode != 0, 'invalid name accepted'
            assert process.poll() is None, 'CLI input executed as code'
            print('RPC CLI: register, switch, off, validation and code-injection checks passed')
        finally:
            process.terminate()
            process.wait(timeout=10)
