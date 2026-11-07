#!/usr/bin/env python3
"""Drive/check all five live snapshots; binary-drive.py --socket SOCKET [--pause 1]. 2026-11-07."""
import argparse, json, subprocess, time
parser=argparse.ArgumentParser()
parser.add_argument('--socket',required=True)
parser.add_argument('--pause',type=float,default=1)
args=parser.parse_args()
def rpc(code):
    result=subprocess.run(['nvim','--server',args.socket,'--remote-expr','luaeval('+json.dumps(code)+')'],capture_output=True,text=True)
    if result.returncode: raise RuntimeError(result.stderr or result.stdout)
    return result.stdout.strip()
rpc('demo.start()')
stages=[(37,37,37,None),(38,37,37,'Locals.counter'),(38,38,37,'Locals.protobuf_wire.decoded.age'),(38,38,38,'Locals.gzip_wire.decoded.age'),(38,38,38,None)]
for index,(counter,proto,gzip,changed) in enumerate(stages):
    if index:
        rpc("(function() local before=demo.stops; require('dap').continue(); assert(vim.wait(10000,function() return demo.stops>before end,10)); return true end)()")
    change='nil' if changed is None else json.dumps(changed)
    result=json.loads(rpc(f'vim.json.encode(demo.await({counter},{proto},{gzip},{change}))'))
    print(f"{result['language']}: stop {result['stop']}, counter={counter}, protobuf.age={proto}, gzip.age={gzip}, changed={changed or 'none'}, exact bytes=641/583",flush=True)
    time.sleep(args.pause)
