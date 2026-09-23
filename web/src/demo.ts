import type { Game, InvitationAPI } from './types';

export class DemoInvitationAPI implements InvitationAPI {
  readonly isDemo=true;
  private authenticated=false;
  private displayName='Anna';
  private email='';
  private game:Game={id:'demo-game',host_name:'Cindy',place:'HUB Silicon Valley',court:'3',starts_at:new Date().toISOString(),target:11,scoring:'sideout',win_by:2,score_a:null,score_b:null,revision:0,my_claim:null,confirmed_by_me:false,confirmation_count:0,participants:[
    {id:'host',slot:0,nickname:'Cindy',display_name:'Cindy',is_me:false,claimed:true},
    {id:'anna',slot:1,nickname:'Anna',display_name:'Guest - Anna',is_me:false,claimed:false},
    {id:'mike',slot:2,nickname:'Mike',display_name:'Guest - Mike',is_me:false,claimed:false},
    {id:'jo',slot:3,nickname:'Jo',display_name:'Guest - Jo',is_me:false,claimed:false},
  ]};
  async signedIn(){return this.authenticated;}
  async accountEmail(){return this.authenticated?this.email:null;}
  async getInvitation(){return structuredClone(this.game);}
  async sendCode(email:string,displayName:string){this.email=email;this.displayName=displayName;}
  async verifyCode(_email:string,code:string){if(code!=='123456')throw new Error('The demo code is 123456.');this.authenticated=true;}
  async requestSpot(_token:string,id:string){
    if(!this.authenticated)throw new Error('Sign in to continue.');
    const person=this.game.participants.find(p=>p.id===id);
    if(!person || person.claimed)throw new Error('That spot is no longer available.');
    this.game.my_claim={id:'demo-claim',participant_id:id,status:'pending'};return this.getInvitation();
  }
  demoApprove(){
    const claim=this.game.my_claim;if(!claim)return;
    const person=this.game.participants.find(p=>p.id===claim.participant_id)!;
    person.claimed=true;person.is_me=true;person.display_name=this.displayName;claim.status='approved';
  }
  demoResult(){this.game.score_a=11;this.game.score_b=8;this.game.revision=1;}
  async confirmScore(_id:string,revision:number){
    if(revision!==this.game.revision || !this.game.participants.some(p=>p.is_me))throw new Error('Refresh this game before confirming.');
    this.game.confirmed_by_me=true;this.game.confirmation_count=1;return this.getInvitation();
  }
  async signOut(){this.authenticated=false;this.game.participants.forEach(p=>p.is_me=false);this.game.my_claim=null;}
  async deleteAccount(){this.game.participants.filter(p=>p.is_me).forEach(p=>{p.display_name='Guest - Deleted player';p.nickname='Deleted player';p.claimed=false;});await this.signOut();}
}
