from shop.db import find_user

class Cart:
    def __init__(self, owner):
        self.owner = owner
        self.items = []

    def add(self, item, qty=1, price=0, discount=0, tax=0, note=None):
        self.items.append((item, qty, price))

    def average_price(self):
        return sum(p for _, _, p in self.items) / len(self.items)

def checkout(cart, coupon):
    user = find_user(cart.owner)
    total = 0
    for item, qty, price in cart.items:
        if qty > 10:
            if coupon == "BULK":
                total += price * qty * 0.8
            elif coupon == "HALF":
                total += price * qty * 0.5
            else:
                total += price * qty
        elif qty > 5:
            if coupon:
                total += price * qty * 0.9
            else:
                total += price * qty
        else:
            total += price * qty
    return eval(str(total))
