import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const payload = await req.json()
    const { customer, shipping, cart } = payload

    if (!customer || !shipping || !cart || cart.length === 0) {
      throw new Error('Invalid order payload')
    }

    // 1. Recalculate totals securely from database
    let subtotal = 0;
    const validatedCart = [];
    for (const item of cart) {
      let realPrice = 0;
      let name = item.name;

      // Try looking up in product_variants first
      const { data: variantData } = await supabaseAdmin
        .from('product_variants')
        .select('price_jmd, name, products(name)')
        .eq('id', item.productId)
        .maybeSingle();

      if (variantData) {
        realPrice = Number(variantData.price_jmd) || 0;
        name = `${variantData.products.name} - ${variantData.name}`;
      } else {
        // Try looking up in products
        const { data: productData } = await supabaseAdmin
          .from('products')
          .select('price_jmd, name')
          .eq('id', item.productId)
          .maybeSingle();

        if (productData) {
          realPrice = Number(productData.price_jmd) || 0;
          name = productData.name;
        } else {
          // If not found in either, throw error to prevent fake IDs
          throw new Error(`Invalid item in cart: ${item.name}`);
        }
      }

      subtotal += (realPrice * item.quantity);
      validatedCart.push({
        ...item,
        price: realPrice,
        name: name
      });
    }

    let shippingCost = 0
    let shippingStatus = 'confirmed'

    if (shipping.deliveryMethod === 'Zipmail') shippingCost = 500
    else if (shipping.deliveryMethod === 'Knutsford') shippingCost = 700
    else if (shipping.deliveryMethod === 'Bearer') shippingCost = 750
    else if (shipping.deliveryMethod === 'Overseas') shippingStatus = 'pending_quote'

    if (subtotal >= 10000 || shipping.deliveryMethod === 'Pickup' || shipping.deliveryMethod === 'Overseas') {
      shippingCost = 0
    }

    const total = subtotal + shippingCost

    // 2. Create Order Number
    const dateStr = new Date().toISOString().slice(0,10).replace(/-/g, '')
    const randomNum = Math.floor(1000 + Math.random() * 9000)
    const orderNumber = `FSB-${dateStr}-${randomNum}`

    // 3. Insert into orders table
    const { data: orderData, error: orderError } = await supabaseAdmin
      .from('orders')
      .insert({
        order_number: orderNumber,
        full_name: customer.fullName,
        phone: customer.phone,
        email: customer.email,
        country: shipping.country,
        address_line_1: shipping.addressLine1,
        address_line_2: shipping.addressLine2,
        city: shipping.city,
        parish: shipping.parish,
        state_province: shipping.stateProvince,
        postal_code: shipping.postalCode,
        delivery_method: shipping.deliveryMethod,
        delivery_notes: shipping.notes,
        subtotal: subtotal,
        shipping_amount: shippingCost,
        shipping_status: shippingStatus,
        total: total,
        payment_method: 'WiPay',
        payment_status: 'pending confirmation',
        order_status: 'received'
      })
      .select('id')
      .single()

    if (orderError) throw orderError
    const orderId = orderData.id

    // 4. Insert into order_items table
    const orderItems = validatedCart.map((item: any) => ({
      order_id: orderId,
      product_id: item.productId,
      product_name: item.name,
      unit_price: item.price,
      quantity: item.quantity,
      line_total: item.price * item.quantity,
      image_url: item.image
    }))

    const { error: itemsError } = await supabaseAdmin
      .from('order_items')
      .insert(orderItems)

    if (itemsError) throw itemsError

    // 5. Send emails via Resend
    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
    const OWNER_EMAIL = Deno.env.get('OWNER_EMAIL') || 'clientemail@example.com'
    const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'For You Skin Bar <orders@orders.foryouskinbar.com>'

    if (RESEND_API_KEY) {
      try {
        const itemsListText = validatedCart.map((item: any, idx: number) => `${idx + 1}. ${item.name} × ${item.quantity} — J$${(item.price * item.quantity).toLocaleString()}`).join('\n')

        const customerHtml = `
          <p>Hi ${customer.fullName},</p>
          <p>Thank you for your order with For You Skin Bar.</p>
          <p><b>Order Number:</b> ${orderNumber}<br>
          <b>Payment Status:</b> Pending confirmation<br>
          <b>Delivery Method:</b> ${shipping.deliveryMethod}</p>
          <p><b>Items:</b><br>${itemsListText.replace(/\n/g, '<br>')}</p>
          <p><b>Subtotal:</b> J$${subtotal.toLocaleString()}<br>
          <b>Shipping:</b> ${shipping.deliveryMethod === 'Overseas' ? 'To be confirmed' : 'J$' + shippingCost.toLocaleString()}<br>
          <b>Final Total:</b> ${shipping.deliveryMethod === 'Overseas' ? 'Pending shipping confirmation' : 'J$' + total.toLocaleString()}</p>
          <p><b>Delivery Address:</b><br>
          ${shipping.addressLine1}<br>
          ${shipping.addressLine2 ? shipping.addressLine2 + '<br>' : ''}
          ${shipping.city}${shipping.stateProvince ? ', ' + shipping.stateProvince : ''}<br>
          ${shipping.parish ? shipping.parish + '<br>' : ''}
          ${shipping.country}</p>
          <p>Please note: this is an order confirmation, not a tax invoice. Payment and delivery will be confirmed by For You Skin Bar.</p>
          <p>Thank you for shopping with us.</p>
        `

        const ownerHtml = `
          <p>A new order was submitted.</p>
          <p><b>Customer:</b><br>
          Name: ${customer.fullName}<br>
          Phone: ${customer.phone}<br>
          Email: ${customer.email}</p>
          <p><b>Delivery:</b><br>
          Method: ${shipping.deliveryMethod}<br>
          Address: ${shipping.addressLine1}, ${shipping.city}, ${shipping.country}<br>
          Postal / ZIP Code: ${shipping.postalCode || 'N/A'}</p>
          <p><b>Order:</b><br>${itemsListText.replace(/\n/g, '<br>')}</p>
          <p>Subtotal: J$${subtotal.toLocaleString()}<br>
          Shipping: ${shipping.deliveryMethod === 'Overseas' ? 'To be confirmed' : 'J$' + shippingCost.toLocaleString()}<br>
          Total: ${shipping.deliveryMethod === 'Overseas' ? 'Pending shipping confirmation' : 'J$' + total.toLocaleString()}</p>
          <p><b>Notes:</b><br>${shipping.notes || 'None'}</p>
        `

        // Send Customer Email
        const resCustomer = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${RESEND_API_KEY}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            from: FROM_EMAIL,
            to: customer.email,
            subject: `Your For You Skin Bar order has been received — ${orderNumber}`,
            html: customerHtml
          })
        })

        // Send Owner Email
        const resOwner = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${RESEND_API_KEY}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            from: FROM_EMAIL,
            to: OWNER_EMAIL,
            subject: `New For You Skin Bar order — ${orderNumber}`,
            html: ownerHtml
          })
        })

        let customerErrorMsg = null
        if (!resCustomer.ok) {
           const resCustomerJson = await resCustomer.json()
           customerErrorMsg = JSON.stringify(resCustomerJson)
        }

        await supabaseAdmin.from('email_logs').insert({
          order_id: orderId,
          recipient: customer.email,
          email_type: 'customer_confirmation',
          status: resCustomer.ok ? 'sent' : 'error',
          error_message: customerErrorMsg
        })
      } catch (err) {
        // Log the failure to send email without rolling back the order
        await supabaseAdmin.from('email_logs').insert({
          order_id: orderId,
          recipient: customer.email,
          email_type: 'customer_confirmation',
          status: 'error',
          error_message: String(err)
        })
      }
    } else {
      await supabaseAdmin.from('email_logs').insert({
        order_id: orderId,
        recipient: customer.email,
        email_type: 'customer_confirmation',
        status: 'pending_resend_setup',
        error_message: 'RESEND_API_KEY missing'
      })
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        order_number: orderNumber,
        grand_total: total
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
