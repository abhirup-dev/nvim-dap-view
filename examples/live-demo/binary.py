# REAL PYTHON BYTES: protobuf + gzip. F5 advances to the next marked snapshot.
# Only counter changes at B, protobuf age at C, gzip age at D; E is unchanged.
from pathlib import Path
root = Path(__file__).resolve().parent

def run():
    unchanged = "Ada"
    counter = 37
    protobuf_wire = (root / "protobuf-37.bin").read_bytes()
    gzip_wire = (root / "gzip-37.bin").read_bytes()
    print("A: initial")  # STOP: initial
    counter = 38
    print("B: only counter changed")  # STOP: counter
    protobuf_wire = (root / "protobuf-38.bin").read_bytes()
    print("C: only protobuf age changed")  # STOP: protobuf
    gzip_wire = (root / "gzip-38.bin").read_bytes()
    print("D: only gzip age changed")  # STOP: gzip
    print("E: no changes", counter, unchanged)  # STOP: unchanged

run()
