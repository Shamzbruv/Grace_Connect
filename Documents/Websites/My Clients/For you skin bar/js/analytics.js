/**
 * analytics.js — Lightweight event tracking for For You Skin Bar
 * Logs events to console in dev, pushes to dataLayer for GTM integration
 */
(function() {
  // Initialize dataLayer for Google Tag Manager
  window.dataLayer = window.dataLayer || [];

  /**
   * Track a custom event
   * @param {string} eventName - Event name (e.g., 'add_to_cart', 'quiz_complete')
   * @param {object} eventData - Additional event data
   */
  window.trackEvent = function(eventName, eventData = {}) {
    const event = {
      event: eventName,
      timestamp: new Date().toISOString(),
      page: window.location.pathname,
      ...eventData
    };

    // Push to GTM dataLayer
    window.dataLayer.push(event);

    // Console log in development
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
      console.log(`📊 Event: ${eventName}`, eventData);
    }
  };

  // ── Auto-track page views ──
  window.trackEvent('page_view', {
    page_title: document.title,
    page_path: window.location.pathname
  });

})();
