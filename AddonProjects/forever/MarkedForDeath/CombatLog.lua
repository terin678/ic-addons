local addonName, ns = ...

-- CombatLog: turns the combat log file on in listed instances; ShouldLog is pure.
-- Owned by lane H (ops). An empty stub from the scaffold (lane S) until that lane
-- fills it; the .toc already lists it, so the lane never edits the .toc.
-- Frame module: calls the client only inside a function registered with
-- ns.OnReady from this file, and returns early on IC_HEADLESS.
