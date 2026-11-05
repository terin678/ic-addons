local addonName, ns = ...

-- Debug: WhyNot(state): the reasons marking will not happen, most fundamental first.
-- Owned by lane A (model). An empty stub from the scaffold (lane S) until that lane
-- fills it; the .toc already lists it, so the lane never edits the .toc.
-- Pure: no client call, ever; every function takes its tables as arguments.
