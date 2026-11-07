#!/usr/bin/env python3
"""Generate real protobuf/gzip fixtures; deps/venv/bin/python binary-fixtures.py. No VPN. 2026-11-07."""
import gzip, hashlib, json, random, string
from pathlib import Path
from google.protobuf import descriptor_pb2 as pb, descriptor_pool, message_factory
root = Path(__file__).resolve().parent
schema = pb.FileDescriptorProto(name='demo.proto', package='example', syntax='proto3')
address = schema.message_type.add(name='Address')
address.field.add(name='city', number=1, type=9, label=1)
person = schema.message_type.add(name='Person')
for name, number, kind, label, type_name in [('name',1,9,1,''),('age',2,5,1,''),('address',3,11,1,'.example.Address'),('tags',4,9,3,''),('padding',5,12,1,'')]:
    field = person.field.add(name=name,number=number,type=kind,label=label)
    if type_name: field.type_name=type_name
pool=descriptor_pool.DescriptorPool(); pool.Add(schema)
Person=message_factory.GetMessageClass(pool.FindMessageTypeByName('example.Person'))
files=pb.FileDescriptorSet(); files.file.add().CopyFrom(schema)
(root/'binary-schema.pb').write_bytes(files.SerializeToString())
random_source=random.Random(42)
padding=''.join(random_source.choice(string.ascii_letters+string.digits) for _ in range(640))
manifest={}
for age in (37,38):
    person=Person(name='Ada',age=age,tags=['debugger','protobuf'],padding=b'\x00\xff'*300)
    person.address.city='Kolkata'
    for kind,data in [('protobuf',person.SerializeToString()),('gzip',gzip.compress(json.dumps({'name':'Ada','age':age,'active':True,'score':1.5,'padding':padding},sort_keys=True).encode(),mtime=0))]:
        name=f'{kind}-{age}.bin'; (root/name).write_bytes(data)
        manifest[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
(root/'binary-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
