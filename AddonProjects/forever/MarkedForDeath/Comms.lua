local addonName, ns = ...

-- Comms: addon messages: hello, rules merge, the published plan.
-- Owned by lane F (comms and lead). An empty stub from the scaffold (lane S) until that lane
-- fills it; the .toc already lists it, so the lane never edits the .toc.
-- Frame module: calls the client only inside a function registered with
-- ns.OnReady from this file, and returns early on IC_HEADLESS.
