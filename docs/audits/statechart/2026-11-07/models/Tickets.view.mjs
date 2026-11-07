// Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
export const title="MCP ticket and sidecar fences";
export const state=v=>({Ticket:v.ticket,Caller:v.client,Wait:v.settled?"settled":"listening",Sidecar:v.sidecar===1?"original":"replacement"});
export const step=a=>({Poll:"caller polls before expiry",Age:"ticket reaches its idle deadline",Expire:"next call collects idle tickets",Cancel:"caller cancels its wait",Finish:"event or timeout settles the wait",Collect:"caller collects its reply",Restart:"you restart the sidecar",OldExit:"old process exit is ignored",Idle:"no work"}[a]||a);
