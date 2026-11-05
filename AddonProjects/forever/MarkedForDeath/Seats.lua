local addonName, ns = ...

-- Seats: who owns each seat: pins, classes, name order.
-- Owned by lane A (model). An empty stub from the scaffold (lane S) until that lane
-- fills it; the .toc already lists it, so the lane never edits the .toc.
-- Pure: no client call, ever; every function takes its tables as arguments.
