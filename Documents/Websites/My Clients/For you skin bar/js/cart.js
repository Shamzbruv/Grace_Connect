/**
 * CartManager — Centralized cart logic for For You Skin Bar
 * Handles add/remove/update, drawer UI, shipping progress, and WhatsApp order generation
 */
class CartManager {
  constructor() {
    this.STORAGE_KEY = 'foryou_cart';
    this.FREE_SHIPPING_THRESHOLD = 10000;
    this.WHATSAPP_NUMBER = '18763094374';
    this.items = JSON.parse(localStorage.getItem(this.STORAGE_KEY)) || [];
    this.initUI();
  }

  // ── Persistence ──
  save() {
    localStorage.setItem(this.STORAGE_KEY, JSON.stringify(this.items));
    this.updateUI();
  }

  // ── Cart Operations ──
  addItem(product, variantName = null, variantPrice = null, quantity = 1) {
    const price = variantPrice !== null ? parseFloat(variantPrice) : product.price;
    const name = variantName ? `${product.name} - ${variantName}` : product.name;
    const cartItemId = variantName ? `${product.id}-${variantName}` : product.id;
    const qtyToAdd = Math.max(1, parseInt(quantity, 10) || 1);

    const existing = this.items.find(i => i.id === cartItemId);
    if (existing) {
      existing.qty += qtyToAdd;
    } else {
      this.items.push({
        id: cartItemId,
        productId: product.id,
        name: name,
        price: price,
        image: product.image,
        category: product.category,
        qty: qtyToAdd
      });
    }
    this.save();
    this.openDrawer();
    this.showAddedFeedback();
  }

  removeItem(id) {
    this.items = this.items.filter(i => i.id !== id);
    this.save();
  }

  updateQty(id, qty) {
    if (qty <= 0) {
      this.removeItem(id);
      return;
    }
    const item = this.items.find(i => i.id === id);
    if (item) {
      item.qty = qty;
      this.save();
    }
  }

  clearCart() {
    this.items = [];
    this.save();
  }

  getTotal() {
    return this.items.reduce((sum, item) => sum + (item.price * item.qty), 0);
  }

  getCount() {
    return this.items.reduce((sum, item) => sum + item.qty, 0);
  }

  getShippingCost() {
    return this.getTotal() >= this.FREE_SHIPPING_THRESHOLD ? 0 : 500;
  }

  getGrandTotal() {
    return this.getTotal() + this.getShippingCost();
  }

  // ── UI Initialization ──
  initUI() {
    this.cartCount = document.getElementById('cartCount');
    this.cartDrawer = document.getElementById('cartDrawer');
    this.cartOverlay = document.getElementById('cartOverlay');
    this.cartItemsList = document.getElementById('cartItemsList');
    this.cartTotal = document.getElementById('cartTotal');
    this.cartFooter = document.getElementById('cartFooter');
    this.shippingProgress = document.getElementById('shippingProgress');

    const cartIconBtn = document.getElementById('cartIconBtn');
    const closeCartBtn = document.getElementById('closeCartBtn');

    if (cartIconBtn) {
      cartIconBtn.addEventListener('click', () => this.openDrawer());
    }
    if (closeCartBtn) {
      closeCartBtn.addEventListener('click', () => this.closeDrawer());
    }

    this.updateUI();
  }

  // ── Drawer Controls ──
  openDrawer() {
    if (this.cartDrawer) this.cartDrawer.classList.add('open');
    if (this.cartOverlay) this.cartOverlay.classList.remove('hidden');
    // Close mobile menu if open
    const mobileMenu = document.getElementById('mobileMenuDrawer');
    if (mobileMenu) mobileMenu.classList.remove('open');
    document.body.style.overflow = 'hidden';
  }

  closeDrawer() {
    if (this.cartDrawer) this.cartDrawer.classList.remove('open');
    if (this.cartOverlay) this.cartOverlay.classList.add('hidden');
    document.body.style.overflow = '';
  }

  showAddedFeedback() {
    // Brief badge pulse
    if (this.cartCount) {
      this.cartCount.classList.add('scale-125');
      setTimeout(() => this.cartCount.classList.remove('scale-125'), 300);
    }
  }

  // ── Render UI ──
  updateUI() {
    // Update badge count
    if (this.cartCount) {
      const count = this.getCount();
      this.cartCount.innerText = count;
      this.cartCount.style.display = count > 0 ? 'flex' : 'none';
    }

    // Render cart items
    if (this.cartItemsList) {
      if (this.items.length === 0) {
        this.cartItemsList.innerHTML = `
          <div class="flex flex-col items-center justify-center h-full text-center py-12">
            <i class="fas fa-bag-shopping text-4xl text-stone-200 mb-4"></i>
            <p class="text-stone-400 font-medium">Your cart is empty</p>
            <a href="shop.html" class="text-amber-800 text-sm mt-2 hover:underline">Continue Shopping →</a>
          </div>`;
      } else {
        this.cartItemsList.innerHTML = this.items.map(item => `
          <div class="flex gap-3 mb-4 pb-4 border-b border-stone-100">
            <img src="${item.image || 'https://placehold.co/100x100/F5EDE1/8B5A2B?text=Product'}" alt="${item.name}" class="w-16 h-16 rounded-xl object-cover flex-shrink-0">
            <div class="flex-1 min-w-0">
              <h4 class="text-sm font-bold text-stone-800 leading-tight truncate">${item.name}</h4>
              <p class="text-amber-800 text-sm font-semibold mt-0.5">J$${item.price.toLocaleString()}</p>
              <div class="flex items-center gap-1 mt-2">
                <button onclick="window.cartManager.updateQty('${item.id}', ${item.qty - 1})" class="w-7 h-7 rounded-full bg-stone-100 hover:bg-stone-200 text-stone-600 flex items-center justify-center text-xs transition">−</button>
                <span class="text-sm font-bold w-8 text-center">${item.qty}</span>
                <button onclick="window.cartManager.updateQty('${item.id}', ${item.qty + 1})" class="w-7 h-7 rounded-full bg-stone-100 hover:bg-stone-200 text-stone-600 flex items-center justify-center text-xs transition">+</button>
              </div>
            </div>
            <div class="flex flex-col items-end justify-between">
              <button onclick="window.cartManager.removeItem('${item.id}')" class="text-stone-300 hover:text-red-500 transition p-1"><i class="fas fa-trash-can text-xs"></i></button>
              <span class="text-sm font-bold text-stone-700">J$${(item.price * item.qty).toLocaleString()}</span>
            </div>
          </div>
        `).join('');
      }
    }

    // Update total
    if (this.cartTotal) {
      this.cartTotal.innerText = 'J$' + this.getTotal().toLocaleString();
    }

    // Shipping progress bar
    if (this.shippingProgress) {
      const total = this.getTotal();
      const remaining = this.FREE_SHIPPING_THRESHOLD - total;
      const progress = Math.min((total / this.FREE_SHIPPING_THRESHOLD) * 100, 100);

      if (this.items.length === 0) {
        this.shippingProgress.innerHTML = '';
      } else if (remaining <= 0) {
        this.shippingProgress.innerHTML = `
          <div class="text-center text-sm text-green-700 font-medium mb-2">
            <i class="fas fa-check-circle mr-1"></i>You've earned FREE shipping!
          </div>`;
      } else {
        this.shippingProgress.innerHTML = `
          <div class="text-center text-xs text-stone-500 mb-1.5">
            Add <strong class="text-amber-800">J$${remaining.toLocaleString()}</strong> more for free shipping
          </div>
          <div class="w-full bg-stone-100 rounded-full h-1.5">
            <div class="bg-amber-700 h-1.5 rounded-full transition-all duration-500" style="width: ${progress}%"></div>
          </div>`;
      }
    }

    // Show/hide footer based on cart state
    if (this.cartFooter) {
      this.cartFooter.style.display = this.items.length > 0 ? 'block' : 'none';
    }
  }

  // ── WhatsApp Order Message Builder ──
  generateWhatsAppOrder(customerInfo = {}) {
    const { name, phone, email, deliveryMethod, address, parish, paymentMethod, notes } = customerInfo;

    let message = `Hello For You Skin Bar, I would like to place an order.\n\n`;
    if (name) message += `*Name:* ${name}\n`;
    if (phone) message += `*Phone:* ${phone}\n`;
    if (email) message += `*Email:* ${email}\n`;
    if (deliveryMethod) message += `*Delivery/Pickup:* ${deliveryMethod}\n`;
    if (address) message += `*Address:* ${address}${parish ? ', ' + parish : ''}\n`;
    if (paymentMethod) message += `*Payment Method:* ${paymentMethod}\n`;

    message += `\n*Order:*\n`;
    this.items.forEach((item, i) => {
      message += `${i + 1}. ${item.name} × ${item.qty} — J$${(item.price * item.qty).toLocaleString()}\n`;
    });

    const subtotal = this.getTotal();
    const shipping = this.getShippingCost();
    message += `\n*Subtotal:* J$${subtotal.toLocaleString()}`;
    message += `\n*Shipping:* ${shipping === 0 ? 'Free' : 'J$' + shipping.toLocaleString()}`;
    message += `\n*Total:* J$${this.getGrandTotal().toLocaleString()}`;

    if (notes) message += `\n\n*Notes:* ${notes}`;

    return message;
  }

  openWhatsAppOrder(customerInfo = {}) {
    const message = this.generateWhatsAppOrder(customerInfo);
    const url = `https://wa.me/${this.WHATSAPP_NUMBER}?text=${encodeURIComponent(message)}`;
    window.open(url, '_blank');
  }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.cartManager = new CartManager();
});

window.addToCartWithVariant = async function(productId) {
  if (window.loadProductsData) await window.loadProductsData();
  const product = window.productsData ? window.productsData.find(p => p.id === productId) : null;
  if (!product) return;
  const select = document.getElementById(`variant-${productId}`);
  const qtyInput = document.getElementById('productQuantity');
  const quantity = qtyInput ? Math.max(1, parseInt(qtyInput.value, 10) || 1) : 1;
  if (select) {
    const opt = select.options[select.selectedIndex];
    window.cartManager.addItem(product, opt.value, opt.getAttribute('data-price'), quantity);
  } else {
    window.cartManager.addItem(product, null, null, quantity);
  }
};
