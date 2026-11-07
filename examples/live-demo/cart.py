# PYTHON: conditional breakpoint + custom JSON decoder
# F5 continue | F10 next | F11 in | F12 out | Space ds scopes / dw watches
# Break only when item['quantity'] > 1: Coffee and Tea; skip Cake.
import json as codec


class CartSummary:
    def __init__(self, name, subtotal, running_total):
        self.data = {"item": name, "subtotal": subtotal, "running_total": running_total}

    def __repr__(self):
        return codec.dumps(self.data)


def checkout(cart):
    total = 0
    payload = CartSummary("ready", 0, 0)
    for item in cart:
        subtotal = item["price"] * item["quantity"]
        total += subtotal
        payload = CartSummary(item["name"], subtotal, total)
        print(payload)  # CONDITIONAL: item['quantity'] > 1
    return total


cart = [
    {"name": "Coffee", "price": 120, "quantity": 2},
    {"name": "Cake", "price": 80, "quantity": 1},
    {"name": "Tea", "price": 60, "quantity": 3},
]
answer = checkout(cart)
print(f"Cart total: {answer}")
