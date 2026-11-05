local addonName, ns = ...

-- Capture: merge observations, caps, export JSON.
-- Owned by lane E (data and capture). An empty stub from the scaffold (lane S) until that lane
-- fills it; the .toc already lists it, so the lane never edits the .toc.
-- Pure: no client call, ever; every function takes its tables as arguments.
