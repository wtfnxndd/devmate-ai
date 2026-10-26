from shop.db import find_user


def order_total(cart, coupon):
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
        else:
            total += price * qty
    return total
