from fastapi import FastAPI
from shop.cart import Cart, checkout

app = FastAPI()

@app.get("/cart/{owner}")
def get_cart(owner: str):
    return Cart(owner).items

@app.post("/checkout")
def do_checkout(owner: str, coupon: str = ""):
    return checkout(Cart(owner), coupon)
