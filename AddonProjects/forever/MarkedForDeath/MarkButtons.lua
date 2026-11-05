local addonName, ns = ...

-- MarkButtons: the secure Mark pack, Clear, Re-mark and Mark mouseover buttons.
-- Owned by lane B (marking runtime). An empty stub from the scaffold (lane S) until that lane
-- fills it; the .toc already lists it, so the lane never edits the .toc.
-- Frame module: calls the client only inside a function registered with
-- ns.OnReady from this file, and returns early on IC_HEADLESS.
