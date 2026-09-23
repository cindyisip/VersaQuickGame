import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Game, InvitationAPI } from './types';

export class SupabaseInvitationAPI implements InvitationAPI {
  readonly isDemo = false;
  private readonly client: SupabaseClient;
  constructor(url: string, publishableKey: string) {
    this.client = createClient(url, publishableKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
    });
  }
  private async rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await this.client.rpc(name, args);
    if (error) throw new Error(error.message);
    return data as T;
  }
  async signedIn(): Promise<boolean> {
    const {data:{session},error} = await this.client.auth.getSession();
    if (error) throw error;
    return Boolean(session);
  }
  async accountEmail():Promise<string|null> { const {data:{session}}=await this.client.auth.getSession();return session?.user.email??null; }
  getInvitation(token: string): Promise<Game> { return this.rpc('get_invitation', {p_token: token}); }
  async sendCode(email: string, displayName: string): Promise<void> {
    const {error} = await this.client.auth.signInWithOtp({email, options:{shouldCreateUser:true, data:{display_name:displayName}}});
    if (error) throw error;
  }
  async verifyCode(email: string, code: string, displayName: string): Promise<void> {
    const {error} = await this.client.auth.verifyOtp({email, token:code, type:'email'});
    if (error) throw error;
    await this.rpc('bootstrap', {p_display_name:displayName});
  }
  requestSpot(token:string, participantId:string):Promise<Game> { return this.rpc('request_spot',{p_token:token,p_participant_id:participantId}); }
  confirmScore(gameId:string, revision:number):Promise<Game> { return this.rpc('confirm_score',{p_game_id:gameId,p_revision:revision}); }
  async signOut():Promise<void> { const {error}=await this.client.auth.signOut({scope:'local'});if(error)throw error; }
  async deleteAccount():Promise<void> { await this.rpc('delete_my_account',{p_confirmation:'DELETE'});await this.client.auth.signOut({scope:'local'}); }
}

export function liveAPI(): InvitationAPI | null {
  const url=import.meta.env.VITE_SUPABASE_URL, key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key || url.includes('YOUR_') || key.includes('YOUR_') || !key.startsWith('sb_publishable_')) return null;
  try { if(new URL(url).protocol!=='https:')return null;return new SupabaseInvitationAPI(url,key); } catch { return null; }
}
