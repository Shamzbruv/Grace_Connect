document.addEventListener('DOMContentLoaded', () => {
  // Read cart data
  const STORAGE_KEY = 'foryou_cart';
  let cart = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  
  const FREE_SHIPPING_THRESHOLD = 10000;
  const WHATSAPP_NUMBER = '18763094374';

  const orderItemsContainer = document.getElementById('orderItems');
  const subtotalEl = document.getElementById('checkoutSubtotal');
  const shippingEl = document.getElementById('checkoutShipping');
  const totalEl = document.getElementById('checkoutTotal');
  const emptyStateEl = document.getElementById('emptyCartState');
  const checkoutFormEl = document.getElementById('checkoutFormWrapper');
  const form = document.getElementById('checkoutForm');
  
  // Dynamic Elements
  const countrySelect = document.getElementById('countrySelect');
  const deliveryRadios = document.getElementsByName('deliveryMethod');
  const addressFieldsWrapper = document.getElementById('addressFieldsWrapper');
  const parishWrapper = document.getElementById('parishWrapper');
  const stateWrapper = document.getElementById('stateWrapper');
  const cityLabel = document.getElementById('cityLabel');
  const postalCodeOptional = document.getElementById('postalCodeOptional');
  
  const localDeliveries = document.querySelectorAll('.delivery-local');
  const overseasDelivery = document.querySelector('.delivery-overseas');
  const overseasRadio = document.querySelector('input[name="deliveryMethod"][value="Overseas"]');

  const successMessage = document.getElementById('successMessage');
  const errorMessage = document.getElementById('errorMessage');
  const successOrderNumber = document.getElementById('successOrderNumber');
  const whatsappFollowupBtn = document.getElementById('whatsappFollowupBtn');

  function getSubtotal() {
    return cart.reduce((sum, item) => sum + (item.price * item.qty), 0);
  }

  function getShipping() {
    const method = document.querySelector('input[name="deliveryMethod"]:checked')?.value;
    if (!method || method === 'Pickup') return 0;
    if (method === 'Overseas') return 0; // TBD
    
    let cost = 0;
    if (method === 'Zipmail') cost = 500;
    else if (method === 'Knutsford') cost = 700;
    else if (method === 'Bearer') cost = 750;
    
    return getSubtotal() >= FREE_SHIPPING_THRESHOLD ? 0 : cost;
  }

  function renderOrderSummary() {
    if (cart.length === 0) {
      emptyStateEl.classList.remove('hidden');
      checkoutFormEl.classList.add('hidden');
      return;
    }

    emptyStateEl.classList.add('hidden');
    checkoutFormEl.classList.remove('hidden');

    orderItemsContainer.innerHTML = cart.map(item => `
      <div class="flex gap-4 mb-4">
        <div class="relative">
          <img src="${item.image}" class="w-16 h-16 rounded-xl object-cover border border-stone-200">
          <span class="absolute -top-2 -right-2 bg-stone-500 text-white text-xs w-5 h-5 rounded-full flex items-center justify-center font-bold">${item.qty}</span>
        </div>
        <div class="flex-1">
          <h4 class="text-sm font-bold text-stone-800 leading-tight">${item.name}</h4>
          <p class="text-stone-500 text-sm mt-1">J$${item.price.toLocaleString()}</p>
        </div>
        <div class="font-bold text-stone-800">
          J$${(item.price * item.qty).toLocaleString()}
        </div>
      </div>
    `).join('');

    const subtotal = getSubtotal();
    const method = document.querySelector('input[name="deliveryMethod"]:checked')?.value;
    const shipping = getShipping();
    const total = subtotal + shipping;

    subtotalEl.innerText = 'J$' + subtotal.toLocaleString();
    
    if (method === 'Overseas') {
        shippingEl.innerText = 'To be confirmed';
        totalEl.innerText = 'Pending confirmation';
    } else {
        shippingEl.innerText = shipping === 0 ? (method === 'Pickup' ? 'J$0' : 'Free') : 'J$' + shipping.toLocaleString();
        totalEl.innerText = 'J$' + total.toLocaleString();
    }
  }

  function toggleCountryFields() {
    const isJamaica = countrySelect.value === 'Jamaica';
    
    if (isJamaica) {
        parishWrapper.classList.remove('hidden');
        document.getElementById('parish').required = true;
        stateWrapper.classList.add('hidden');
        document.getElementById('stateProvince').required = false;
        cityLabel.innerHTML = 'City / Town <span class="req-star">*</span>';
        postalCodeOptional.classList.remove('hidden');
        document.getElementById('postalCode').required = false;

        localDeliveries.forEach(el => el.classList.remove('hidden'));
        overseasDelivery.classList.add('hidden');
        overseasRadio.checked = false;
        
        // Auto-select first local if none selected
        if (!document.querySelector('input[name="deliveryMethod"]:checked')) {
            document.querySelector('input[value="Zipmail"]').checked = true;
        }
    } else {
        parishWrapper.classList.add('hidden');
        document.getElementById('parish').required = false;
        stateWrapper.classList.remove('hidden');
        document.getElementById('stateProvince').required = true;
        cityLabel.innerHTML = 'City <span class="req-star">*</span>';
        postalCodeOptional.classList.add('hidden');
        document.getElementById('postalCode').required = true;

        localDeliveries.forEach(el => el.classList.add('hidden'));
        overseasDelivery.classList.remove('hidden');
        overseasRadio.checked = true;
    }
    renderOrderSummary();
  }

  // Event Listeners
  if (countrySelect) {
      countrySelect.addEventListener('change', toggleCountryFields);
  }

  Array.from(deliveryRadios).forEach(radio => {
    radio.addEventListener('change', (e) => {
      const isPickup = e.target.value === 'Pickup';
      const inputs = addressFieldsWrapper.querySelectorAll('input, select');
      
      if (isPickup) {
        addressFieldsWrapper.classList.add('opacity-50', 'pointer-events-none');
        inputs.forEach(input => input.required = false);
      } else {
        addressFieldsWrapper.classList.remove('opacity-50', 'pointer-events-none');
        inputs.forEach(input => {
            if (input.id === 'addressLine2' || input.id === 'postalCode') {
                if (input.id === 'postalCode' && countrySelect.value !== 'Jamaica') {
                    input.required = true;
                }
            } else if (input.id === 'stateProvince' && countrySelect.value === 'Jamaica') {
                input.required = false;
            } else if (input.id === 'parish' && countrySelect.value !== 'Jamaica') {
                input.required = false;
            } else {
                input.required = true;
            }
        });
      }
      renderOrderSummary();
    });
  });

  // Handle form submission
  if (form) {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      if (cart.length === 0) return;

      const submitBtn = form.querySelector('button[type="submit"]');
      const originalBtnText = submitBtn.innerHTML;
      submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Submitting your order...';
      submitBtn.disabled = true;
      errorMessage.classList.add('hidden');
      successMessage.classList.add('hidden');

      const formData = new FormData(form);
      const data = Object.fromEntries(formData.entries());

      // Prepare payload exactly as requested
      const payload = {
        customer: {
          fullName: data.fullName,
          phone: data.phone,
          email: data.email
        },
        shipping: {
          country: data.country,
          addressLine1: data.addressLine1,
          addressLine2: data.addressLine2,
          city: data.city,
          parish: data.parish,
          stateProvince: data.stateProvince,
          postalCode: data.postalCode,
          deliveryMethod: data.deliveryMethod,
          notes: data.notes
        },
        cart: cart.map(item => ({
          productId: item.id || item.productId || item.name,
          name: item.name,
          price: item.price,
          quantity: item.qty,
          image: item.image
        }))
      };

      try {
        if (!window.supabase) {
          throw new Error("Supabase client is not initialized.");
        }

        // Use fetch directly to Supabase Edge Function
        const supabaseUrl = window.supabase.supabaseUrl;
        const supabaseAnonKey = window.supabase.supabaseKey;

        const response = await fetch(`${supabaseUrl}/functions/v1/create-order`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${supabaseAnonKey}`,
            'apikey': supabaseAnonKey
          },
          body: JSON.stringify(payload)
        });

        if (!response.ok) {
            const errData = await response.json();
            throw new Error(errData.error || 'Failed to submit order.');
        }

        const result = await response.json();
        const orderNumber = result.order_number || result.orderNumber || 'PENDING';

        // Show success UI
        form.reset();
        successOrderNumber.innerText = orderNumber;
        
        let message = `Hello For You Skin Bar, I just placed an order on the website.\n\n`;
        message += `*Order Number:* ${orderNumber}\n`;
        message += `*Name:* ${data.fullName}\n`;
        
        const url = `https://wa.me/${WHATSAPP_NUMBER}?text=${encodeURIComponent(message)}`;
        whatsappFollowupBtn.href = url;
        
        successMessage.classList.remove('hidden');
        submitBtn.classList.add('hidden');

        // Clear cart ONLY after success
        localStorage.removeItem(STORAGE_KEY);
        cart = [];
        if (window.cartManager) window.cartManager.clearCart();
        
      } catch (err) {
        console.error(err);
        errorMessage.innerText = 'Something went wrong while submitting your order. Please try again or contact us on WhatsApp. (' + err.message + ')';
        errorMessage.classList.remove('hidden');
      } finally {
        submitBtn.innerHTML = originalBtnText;
        submitBtn.disabled = false;
      }
    });
  }

  // Initial render
  toggleCountryFields();
  renderOrderSummary();
});
