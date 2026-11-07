#!/usr/bin/env python3
"""Real protobuf/gzip binary stdin -> JSON; run with deps/venv/bin/python. 2026-11-07."""
import gzip, hashlib, json, sys
from pathlib import Path
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory, json_format
raw=sys.stdin.buffer.read(1048577)
if len(raw)>1048576: raise ValueError('input too large')
if sys.argv[1]=='gzip':
    value=json.loads(gzip.decompress(raw))
else:
    files=descriptor_pb2.FileDescriptorSet.FromString((Path(__file__).parent/'binary-schema.pb').read_bytes())
    pool=descriptor_pool.DescriptorPool()
    for file in files.file: pool.Add(file)
    Person=message_factory.GetMessageClass(pool.FindMessageTypeByName('example.Person'))
    value=json_format.MessageToDict(Person.FromString(raw),preserving_proto_field_name=True)
print(json.dumps({'decoded':value,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}))
