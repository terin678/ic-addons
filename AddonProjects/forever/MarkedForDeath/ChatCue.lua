local addonName, ns = ...

-- ChatCue: a sound on one word in chat; Matches is pure.
-- Owned by lane D (deaths and chat). An empty stub from the scaffold (lane S) until that lane
-- fills it; the .toc already lists it, so the lane never edits the .toc.
-- Frame module: calls the client only inside a function registered with
-- ns.OnReady from this file, and returns early on IC_HEADLESS.
