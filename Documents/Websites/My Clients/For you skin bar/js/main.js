/**
 * main.js — Shared UI logic for For You Skin Bar
 * Handles mobile menu, nav effects, scroll reveal, newsletter, and global event delegation
 */
document.addEventListener('DOMContentLoaded', () => {

  // ── Mobile Menu Drawer ──
  const mobileMenuDrawer = document.getElementById('mobileMenuDrawer');
  const mobileMenuBtn = document.getElementById('mobileMenuBtn');
  const closeMobileMenuBtn = document.getElementById('closeMobileMenuBtn');
  const cartOverlay = document.getElementById('cartOverlay');

  function openMobileMenu() {
    if (mobileMenuDrawer) mobileMenuDrawer.classList.add('open');
    if (cartOverlay) cartOverlay.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
  }

  function closeMobileMenu() {
    if (mobileMenuDrawer) mobileMenuDrawer.classList.remove('open');
    // Only hide overlay if cart drawer is also closed
    const cartDrawer = document.getElementById('cartDrawer');
    if (cartOverlay && (!cartDrawer || !cartDrawer.classList.contains('open'))) {
      cartOverlay.classList.add('hidden');
    }
    document.body.style.overflow = '';
  }

  if (mobileMenuBtn) {
    mobileMenuBtn.addEventListener('click', openMobileMenu);
  }
  if (closeMobileMenuBtn) {
    closeMobileMenuBtn.addEventListener('click', closeMobileMenu);
  }

  // Overlay click closes both mobile menu and cart
  if (cartOverlay) {
    cartOverlay.addEventListener('click', () => {
      closeMobileMenu();
      if (window.cartManager) window.cartManager.closeDrawer();
    });
  }

  // ── Nav Glass Effect on Scroll ──
  const nav = document.querySelector('.glass-nav');
  if (nav) {
    window.addEventListener('scroll', () => {
      if (window.scrollY > 20) {
        nav.classList.add('shadow-md');
      } else {
        nav.classList.remove('shadow-md');
      }
    }, { passive: true });
  }

  // ── Safe Scroll Reveal Animation ──
  // This animation system does not rewrite page structure or move images/forms.
  // It only adds lightweight classes and reveals content as it enters the viewport.
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const supportsObserver = 'IntersectionObserver' in window;

  function isSafeAnimationTarget(el) {
    return el &&
      !el.closest('#cartDrawer') &&
      !el.closest('#mobileMenuDrawer') &&
      !el.closest('script') &&
      !el.closest('style');
  }

  function prepareScrollAnimations(root = document) {
    if (prefersReducedMotion) return;

    const panels = root.querySelectorAll ? root.querySelectorAll('main section, main > div') : [];
    panels.forEach((el) => {
      if (!isSafeAnimationTarget(el)) return;
      if (!el.classList.contains('scroll-reveal') && !el.classList.contains('reveal-panel')) {
        el.classList.add('scroll-reveal');
      }
      scrollObserver.observe(el);
    });

    const cardSelectors = [
      '.product-card',
      '.value-card',
      '.ingredient-card-about',
      '.ingredient-card',
      '.trust-item',
      '.faq-item',
      '.reward-card',
      '.blog-card',
      '#blogPreview > a',
      '#shopGrid > *',
      '#productGrid > *'
    ].join(',');

    const cards = root.querySelectorAll ? root.querySelectorAll(cardSelectors) : [];
    cards.forEach((el) => {
      if (!isSafeAnimationTarget(el)) return;
      el.classList.add('reveal-card');
      const siblings = Array.from(el.parentElement ? el.parentElement.children : []);
      const index = Math.max(0, siblings.indexOf(el));
      el.style.setProperty('--reveal-delay', `${Math.min(index * 70, 420)}ms`);
      scrollObserver.observe(el);
    });
  }

  const scrollObserver = supportsObserver
    ? new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('revealed');
            scrollObserver.unobserve(entry.target);
          }
        });
      }, { threshold: 0.06, rootMargin: '0px 0px -8% 0px' })
    : null;

  if (prefersReducedMotion || !supportsObserver) {
    document.querySelectorAll('.scroll-reveal, .reveal-card, .reveal-panel').forEach((el) => {
      el.classList.add('revealed');
    });
  } else {
    document.body.classList.add('animations-ready');
    prepareScrollAnimations(document);

    const mainEl = document.querySelector('main');
    if (mainEl && 'MutationObserver' in window) {
      const mutationObserver = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          mutation.addedNodes.forEach((node) => {
            if (node.nodeType === 1) {
              prepareScrollAnimations(node);
              if (node.parentElement) prepareScrollAnimations(node.parentElement);
            }
          });
        });
      });
      mutationObserver.observe(mainEl, { childList: true, subtree: true });
    }
  }

  // ── Newsletter Form ──
  const newsletterForm = document.getElementById('newsletterForm');
  if (newsletterForm) {
    newsletterForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const email = newsletterForm.querySelector('input[type="email"]').value;
      if (email) {
        // Track the event
        if (window.trackEvent) window.trackEvent('newsletter_signup', { email });

        // Open WhatsApp with subscription message
        const message = `Hi For You Skin Bar! I'd like to join the Glow Letters newsletter. My email is: ${email}`;
        window.open(`https://wa.me/18763094374?text=${encodeURIComponent(message)}`, '_blank');

        // Show success feedback
        const btn = newsletterForm.querySelector('button');
        const originalText = btn.innerHTML;
        btn.innerHTML = '✓';
        btn.classList.add('bg-green-600');
        newsletterForm.querySelector('input').value = '';
        setTimeout(() => {
          btn.innerHTML = originalText;
          btn.classList.remove('bg-green-600');
        }, 2000);
      }
    });
  }

  // ── Global Add to Cart (Event Delegation) ──
  document.addEventListener('click', async (e) => {
    const addBtn = e.target.closest('[data-add-to-cart]');
    if (addBtn && window.cartManager) {
      if (window.loadProductsData) await window.loadProductsData();
      if (window.productsData) {
        const id = parseInt(addBtn.dataset.addToCart);
        const product = window.productsData.find(p => p.id === id);
        if (product) {
          window.cartManager.addItem(product);
          // Button feedback
          addBtn.style.transform = 'scale(0.95)';
          setTimeout(() => addBtn.style.transform = '', 200);
        }
      }
    }
  });

  // ── Highlight active nav link ──
  const currentPage = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.glass-nav a, #mobileMenuDrawer a').forEach(link => {
    const href = link.getAttribute('href');
    if (href === currentPage) {
      link.classList.add('text-amber-800');
      link.classList.remove('text-stone-700');
    }
  });

});

// ── Global Helper Functions ──
window.showGlow = function(el) {
  el.style.transform = 'scale(0.95)';
  setTimeout(() => el.style.transform = '', 200);
};

window.handleAddToCart = async function(id, btnElement) {
  if (window.cartManager) {
    if (window.loadProductsData) await window.loadProductsData();
    if (window.productsData) {
      const product = window.productsData.find(p => p.id === id);
      if (product) {
        window.cartManager.addItem(product);
        if (btnElement) window.showGlow(btnElement);
      }
    }
  }
};

// Open WhatsApp with a custom message
window.openWhatsApp = function(message) {
  const url = `https://wa.me/18763094374?text=${encodeURIComponent(message)}`;
  window.open(url, '_blank');
};
