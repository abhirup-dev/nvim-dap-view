// Saved tab identity under tabmove without a TabEnter event; Statechart view. 2026-11-07; no VPN.
export const title='Saved marker after moving a tab';
export const state=v=>v.phase==='live'||v.phase==='saved'?v.phase+(v.pages[1]==='debug'?' / debugger moved first':' / original order'):v.phase==='restored'?'restored / '+v.owned+' claimed':Object.values(v.pages).includes('user')?'closed / user tab survives':'closed / user tab lost';
export const step=a=>({Reorder:'you move the debugger tab without switching tabs',Save:'you save the stale index',Restore:'the saved index selects its restored tab',Close:'the claimed tab closes',Done:'finished'}[a]||a);
