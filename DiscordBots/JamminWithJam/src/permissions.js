/**
 * Whether a WoW character name is on the officers list. Pure: the caller
 * reads config.officers and passes it in, so a test never has to touch disk.
 *
 * This is the only real enforcement in the whole system -- the addon's own
 * greyed-out button is a courtesy, not a gate, since anyone can type the
 * trigger line by hand. Names are compared case-insensitively because chat
 * logs and config files are typed by different people at different times.
 */
export function isOfficerAllowed(officers, senderName) {
  if (!Array.isArray(officers) || typeof senderName !== "string") return false;
  const target = senderName.trim().toLowerCase();
  if (target === "") return false;
  return officers.some((name) => typeof name === "string" && name.trim().toLowerCase() === target);
}
