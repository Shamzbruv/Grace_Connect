// NOTE: Make sure the Supabase CDN script is loaded before this file in your HTML.
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>

const SUPABASE_URL = 'https://xftnfbeembjrhezvzquu.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_G6Y_BilXMYBxKY99SeIARQ_rl_ZMsgt';

if (window.supabase) {
    window.supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
} else {
    console.error("Supabase CDN script not loaded. Please add the script tag.");
}
