import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL, key=import.meta.env.VITE_SUPABASE_ANON_KEY;
export const supabase=url?.startsWith('https://')&&key&&!key.startsWith('YOUR_')?createClient(url,key):null;
