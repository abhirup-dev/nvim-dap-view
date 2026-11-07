#!/usr/bin/env python3
"""Build a descriptor and actual serialized protobuf fixtures using the protobuf runtime."""
from pathlib import Path
from google.protobuf import descriptor_pb2 as pb, descriptor_pool, message_factory

root = Path(__file__).resolve().parent
schema = pb.FileDescriptorProto(name='fixture.proto', package='example', syntax='proto3')
address = schema.message_type.add(name='Address')
address.field.add(name='city', number=1, type=9, label=1)
person = schema.message_type.add(name='Person')
for name, number, kind, label, type_name in [
    ('name', 1, 9, 1, ''), ('age', 2, 5, 1, ''),
    ('address', 3, 11, 1, '.example.Address'), ('tags', 4, 9, 3, ''), ('padding', 5, 12, 1, ''),
]:
    field = person.field.add(name=name, number=number, type=kind, label=label)
    if type_name:
        field.type_name = type_name
pool = descriptor_pool.DescriptorPool()
pool.Add(schema)
Person = message_factory.GetMessageClass(pool.FindMessageTypeByName('example.Person'))
files = pb.FileDescriptorSet()
files.file.add().CopyFrom(schema)
(root / 'fixture.pb').write_bytes(files.SerializeToString())
for age in (37, 38):
    message = Person(name='Ada', age=age, tags=['debugger', 'protobuf'], padding=b'\x00\xff' * 300)
    message.address.city = 'Kolkata'
    (root / f'person-{age}.bin').write_bytes(message.SerializeToString())
(root / 'malformed.bin').write_bytes(b'\x0a\xff')
