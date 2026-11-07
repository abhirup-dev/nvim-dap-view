// Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
export const title="Yielding replies";
export const state=v=>[v.kind,v.phase+(v.epoch?" / changed context":"")+(!v.requested?" / request replaced":"")+(!v.present?" / watch removed":"")+(v.published?" / published":"")];
export const step=a=>({Begin:"you request a value",ContextChanges:"session, frame or decoder profile changes",RequestChanges:"you replace the requested view or expression",RemoveWatch:"you remove the watch",Reply:"the adapter replies",Done:"finished"}[a]||a);
