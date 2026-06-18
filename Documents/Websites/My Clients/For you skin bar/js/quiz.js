document.addEventListener('DOMContentLoaded', () => {
  const quizContainer = document.getElementById('quizContainer');
  const quizResults = document.getElementById('quizResults');
  const progressFill = document.getElementById('quizProgressFill');
  const stepCounter = document.getElementById('stepCounter');
  const prevBtn = document.getElementById('prevBtn');
  const nextBtn = document.getElementById('nextBtn');
  
  if (!quizContainer) return; // Not on quiz page

  let currentStep = 1;
  const totalSteps = 6;
  let answers = {};

  // Initialize UI
  updateUI();

  // Track Start
  if (window.trackEvent) window.trackEvent('quiz_start');

  // Handle Option Clicks
  document.querySelectorAll('.quiz-option').forEach(option => {
    option.addEventListener('click', function() {
      // Get the name of the radio group
      const input = this.querySelector('input');
      const name = input.name;
      
      // Deselect siblings
      document.querySelectorAll(`input[name="${name}"]`).forEach(siblingInput => {
        siblingInput.closest('.quiz-option').classList.remove('selected');
      });

      // Select this one
      this.classList.add('selected');
      input.checked = true;
      answers[name] = input.value;

      // Auto advance
      setTimeout(() => {
        if (currentStep < totalSteps) {
          currentStep++;
          updateUI();
        }
      }, 300);
    });
  });

  // Navigation Buttons
  if (prevBtn) {
    prevBtn.addEventListener('click', () => {
      if (currentStep > 1) {
        currentStep--;
        updateUI();
      }
    });
  }

  if (nextBtn) {
    nextBtn.addEventListener('click', () => {
      // Check if current step has an answer
      const currentInputs = document.querySelectorAll(`.quiz-step[data-step="${currentStep}"] input:checked`);
      if (currentInputs.length === 0) {
        alert("Please select an option to continue.");
        return;
      }

      if (currentStep < totalSteps) {
        currentStep++;
        updateUI();
      } else {
        generateResults();
      }
    });
  }

  function updateUI() {
    // Progress
    const progress = (currentStep / totalSteps) * 100;
    if (progressFill) progressFill.style.width = `${progress}%`;
    if (stepCounter) stepCounter.innerText = `Step ${currentStep} of ${totalSteps}`;

    // Show/Hide steps
    document.querySelectorAll('.quiz-step').forEach(step => {
      if (parseInt(step.dataset.step) === currentStep) {
        step.classList.remove('hidden');
        step.classList.add('animate-fade-in');
      } else {
        step.classList.add('hidden');
        step.classList.remove('animate-fade-in');
      }
    });

    // Buttons
    if (prevBtn) {
      if (currentStep === 1) prevBtn.classList.add('opacity-0', 'pointer-events-none');
      else prevBtn.classList.remove('opacity-0', 'pointer-events-none');
    }

    if (nextBtn) {
      if (currentStep === totalSteps) {
        nextBtn.innerHTML = 'See Results ✨';
        nextBtn.classList.remove('bg-stone-200', 'text-stone-700');
        nextBtn.classList.add('bg-amber-800', 'text-white');
      } else {
        nextBtn.innerHTML = 'Next →';
        nextBtn.classList.add('bg-stone-200', 'text-stone-700');
        nextBtn.classList.remove('bg-amber-800', 'text-white');
      }
    }
  }

  async function generateResults() {
    quizContainer.classList.add('hidden');
    quizResults.classList.remove('hidden');
    
    // Scroll to top
    window.scrollTo({ top: 0, behavior: 'smooth' });

    // Track Complete
    if (window.trackEvent) window.trackEvent('quiz_complete', answers);

    // Analyze and map answers
    const concernMap = {
      'Fade dark spots': 'dark-spots',
      'Reduce acne & breakouts': 'acne',
      'Brighten dull skin': 'glow',
      'Smooth rough texture': 'texture',
      'Moisturize dry skin': 'dryness',
      'Build a simple routine': 'glow'
    };
    const targetConcern = concernMap[answers.goal] || 'glow';
    
    let targetType = answers.type.toLowerCase();
    if (targetType === 'not sure') targetType = 'normal';

    // Ensure products are loaded from Supabase
    if (window.loadProductsData) await window.loadProductsData();
    const products = window.productsData || [];

    // Filter helpers
    const getProduct = (step, fallbackCategory) => {
      let matches = products.filter(p => p.routineStep === step && p.skinType.includes(targetType));
      
      // Try to find exact concern match
      let exact = matches.filter(p => p.skinConcern.includes(targetConcern));
      if (exact.length > 0) return exact[0];
      
      // Fallback
      if (matches.length > 0) return matches[0];
      
      // Ultimate fallback
      return products.find(p => p.category === fallbackCategory) || products[0];
    };

    // Build Routine
    let routine = [];
    
    if (answers.focus === 'Mostly face care' || answers.focus === 'Both face and body') {
      const cleanser = getProduct('cleanse', 'Face Care');
      const treatment = getProduct('treat', 'Serums & Oils');
      const moisturizer = getProduct('moisturize', 'Face Care');
      
      routine.push({ step: 'Step 1: Cleanse', desc: 'Remove impurities gently.', product: cleanser });
      routine.push({ step: 'Step 2: Treat', desc: `Target ${targetConcern.replace('-', ' ')}.`, product: treatment });
      routine.push({ step: 'Step 3: Moisturize', desc: 'Lock in hydration and glow.', product: moisturizer });
    }

    if (answers.focus === 'Mostly body care' || answers.focus === 'Both face and body') {
      const bodyExfoliant = getProduct('exfoliate', 'Scrubs');
      const bodyMoisturizer = getProduct('moisturize', 'Body Care');
      
      routine.push({ step: 'Body Step 1: Polish', desc: 'Smooth away dead skin.', product: bodyExfoliant });
      routine.push({ step: 'Body Step 2: Glow', desc: 'Deeply nourish and seal.', product: bodyMoisturizer });
    }

    // Render Results
    const summaryText = document.getElementById('resultSummary');
    summaryText.innerHTML = `Based on your answers, we've built a routine specifically for <strong>${answers.type.toLowerCase()}</strong> skin to help <strong>${answers.goal.toLowerCase()}</strong>.`;

    const grid = document.getElementById('routineGrid');
    let totalValue = 0;
    
    grid.innerHTML = routine.map(r => {
      // Safely access product properties since some could be undefined if db doesn't match expected data
      if (!r.product) return '';
      totalValue += r.product.price || 0;
      return `
        <div class="bg-white rounded-3xl p-6 shadow-sm border border-amber-50 flex flex-col md:flex-row gap-6 items-center">
          <div class="w-full md:w-1/3 shrink-0 text-center">
            <h4 class="font-bold text-amber-800 mb-1">${r.step}</h4>
            <p class="text-xs text-stone-500 mb-4">${r.desc}</p>
            <img src="${r.product.image}" class="w-full h-40 object-cover rounded-2xl" alt="${r.product.name}">
          </div>
          <div class="w-full md:w-2/3">
            <h3 class="font-bold text-xl mb-2">${r.product.name}</h3>
            <p class="text-amber-800 font-bold mb-3">J$${(r.product.price || 0).toLocaleString()}</p>
            <p class="text-stone-600 text-sm mb-4">${r.product.description}</p>
            <div class="bg-amber-50 rounded-xl p-4">
              <p class="text-sm"><strong>Why it's perfect for you:</strong> Formulated with ${(r.product.ingredients || []).join(', ')} to directly address ${targetConcern.replace('-', ' ')} while respecting your ${targetType} skin barrier.</p>
            </div>
          </div>
        </div>
      `;
    }).join('');

    document.getElementById('routineTotal').innerText = `Total Routine Value: J$${totalValue.toLocaleString()}`;

    // Add All Button Logic
    document.getElementById('addAllBtn').onclick = () => {
      routine.forEach(r => {
        if (r.product && window.cartManager) window.cartManager.addItem(r.product);
      });
      // Show drawer is handled by CartManager
    };

    // WhatsApp Button Logic
    document.getElementById('sendWhatsAppBtn').onclick = () => {
      let message = `Hi For You Skin Bar! I just took the Skin Quiz and wanted to ask about my recommended routine:\n\n`;
      routine.forEach(r => {
        if (r.product) message += `* ${r.product.name}\n`;
      });
      window.openWhatsApp(message);
    };
  }
});
