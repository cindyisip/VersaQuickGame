export interface Participant {
  id: string; slot: number; nickname: string; display_name: string;
  account_id?: string | null; is_me: boolean; claimed: boolean;
}
export interface Claim { id: string; participant_id: string; status: 'pending' | 'approved' | 'declined' }
export interface Game {
  id: string; host_id?: string; host_name: string; place: string; court: string;
  game_type?: 'doubles' | 'singles';
  starts_at: string; target: number; scoring: 'sideout' | 'rally'; win_by: number;
  score_a: number | null; score_b: number | null; revision: number;
  participants: Participant[]; my_claim: Claim | null;
  confirmed_by_me: boolean; confirmation_count: number;
}
export interface InvitationAPI {
  isDemo: boolean;
  signedIn(): Promise<boolean>;
  accountEmail(): Promise<string | null>;
  getInvitation(token: string): Promise<Game>;
  sendCode(email: string, displayName: string): Promise<void>;
  verifyCode(email: string, code: string, displayName: string): Promise<void>;
  requestSpot(token: string, participantId: string): Promise<Game>;
  confirmScore(gameId: string, revision: number): Promise<Game>;
  signOut(): Promise<void>;
  deleteAccount(): Promise<void>;
  demoApprove?(): void;
  demoResult?(): void;
}
