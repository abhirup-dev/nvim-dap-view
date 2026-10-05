package main

import (
	"fmt"
	"os"
)

type Envelope struct{ Payload []byte }

func main() {
	first, _ := os.ReadFile("person-37.bin")
	second, _ := os.ReadFile("person-38.bin")
	bad, _ := os.ReadFile("malformed.bin")
	wrapper := Envelope{Payload: first}
	fmt.Println(len(wrapper.Payload)) // BREAK first
	wrapper.Payload = second
	fmt.Println(len(wrapper.Payload)) // BREAK changed
	wrapper.Payload = bad
	fmt.Println(len(wrapper.Payload)) // BREAK malformed
}
