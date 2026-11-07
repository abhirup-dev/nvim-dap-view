// GO: the same conditional-breakpoint and decoder demo with real Delve.
// F5 continue | F10 next | Space ds scopes / dw watches / db breakpoints
package main

import "fmt"

type Item struct {
	Name            string
	Price, Quantity int
}

func checkout(cart []Item) int {
	total := 0
	payload := "{}"
	for _, item := range cart {
		subtotal := item.Price * item.Quantity
		total += subtotal
		payload = fmt.Sprintf(`{"item":%q,"subtotal":%d,"running_total":%d}`, item.Name, subtotal, total)
		fmt.Println(payload) // CONDITIONAL: item.Quantity > 1
	}
	return total
}

func main() {
	cart := []Item{{"Coffee", 120, 2}, {"Cake", 80, 1}, {"Tea", 60, 3}}
	answer := checkout(cart)
	fmt.Println("Cart total:", answer)
}
