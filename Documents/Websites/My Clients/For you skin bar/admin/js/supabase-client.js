import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm'

// Initialize Supabase Client
// Replace these with your actual Supabase project URL and anon key from the dashboard.
const supabaseUrl = 'https://xftnfbeembjrhezvzquu.supabase.co';
const supabaseKey = 'sb_publishable_G6Y_BilXMYBxKY99SeIARQ_rl_ZMsgt';

// Use sessionStorage if user unchecked "Stay signed in"
const storage = window.localStorage.getItem('foryou_remember') === 'false' ? window.sessionStorage : window.localStorage;

export const supabase = createClient(supabaseUrl, supabaseKey, {
    auth: {
        storage,
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: true
    }
});

// Helper function to check if user is logged in
export async function checkAuth() {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
        window.location.href = '/admin/login.html';
        return null;
    }
    
    // Verify admin role
    const { data: profile } = await supabase
        .from('profiles')
        .select('role')
        .eq('id', session.user.id)
        .single();
        
    if (!profile || !['owner', 'admin', 'staff'].includes(profile.role)) {
        alert('Access denied. Admin privileges required.');
        await supabase.auth.signOut();
        window.location.href = '/admin/login.html';
        return null;
    }
    return session;
}

// Helper to format currency
export function formatCurrency(amount) {
    return new Intl.NumberFormat('en-JM', {
        style: 'currency',
        currency: 'JMD'
    }).format(amount);
}
