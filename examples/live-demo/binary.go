// REAL GO BYTES: protobuf + gzip. F5 advances to the next marked snapshot.
// Only counter changes at B, protobuf age at C, gzip age at D; E is unchanged.
package main

import (
	"fmt"
	"os"
)

func main() {
	unchanged := "Ada"
	counter := 37
	protobuf_wire, _ := os.ReadFile("protobuf-37.bin")
	gzip_wire, _ := os.ReadFile("gzip-37.bin")
	fmt.Println("A: initial") // STOP: initial
	counter = 38
	fmt.Println("B: only counter changed") // STOP: counter
	protobuf_wire, _ = os.ReadFile("protobuf-38.bin")
	fmt.Println("C: only protobuf age changed") // STOP: protobuf
	gzip_wire, _ = os.ReadFile("gzip-38.bin")
	fmt.Println("D: only gzip age changed")                                              // STOP: gzip
	fmt.Println("E: no changes", counter, unchanged, len(protobuf_wire), len(gzip_wire)) // STOP: unchanged
}
