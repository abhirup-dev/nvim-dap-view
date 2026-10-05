#!/usr/bin/env python3
"""Descriptor-backed protobuf stdin -> JSON stdout. No compiler needed at runtime."""
import argparse
import sys
from google.protobuf import descriptor_pb2, descriptor_pool, json_format, message_factory

parser = argparse.ArgumentParser()
parser.add_argument('--descriptor', required=True)
parser.add_argument('--type', required=True)
args = parser.parse_args()
try:
    descriptor = descriptor_pb2.FileDescriptorSet.FromString(open(args.descriptor, 'rb').read())
    pool = descriptor_pool.DescriptorPool()
    pending = list(descriptor.file)
    while pending:
        left = []
        for item in pending:
            try:
                pool.Add(item)
            except TypeError:
                left.append(item)
        if len(left) == len(pending):
            raise ValueError('unresolved schema dependencies')
        pending = left
    cls = message_factory.GetMessageClass(pool.FindMessageTypeByName(args.type))
    message = cls.FromString(sys.stdin.buffer.read())
    print(json_format.MessageToJson(message, preserving_proto_field_name=True))
except Exception as exc:
    print(f'protobuf: {exc}', file=sys.stderr)
    sys.exit(1)
