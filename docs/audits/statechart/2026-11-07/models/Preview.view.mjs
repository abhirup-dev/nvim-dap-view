// Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
export const title='Preview mutation boundary'; export const state=v=>v.channel+' / '+(v.sent?'preview sent to adapter':v.phase); export const step=a=>a==='Edit'?'you try to edit a preview':'finished';
