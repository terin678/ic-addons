import { matchTrigger } from "./chatLogParser.js";
import { secondsUntilReady } from "./cooldowns.js";
import { isOfficerAllowed } from "./permissions.js";

/**
 * Pure. Turns one already-parsed chat line into a decision:
 *   - null            the line was not a trigger at all; not worth logging
 *   - { skip, reason } it was a trigger, but something is in the way
 *   - { play, sender } go play this command's sound
 *
 * Widest reason first, same rule as the addon's Sounds.BlockReason: unknown
 * id before permission before cooldown, so the reason in the log is always
 * the first thing actually wrong rather than whichever check happened to
 * run last.
 */
export function decide(parsedLine, config, cooldownState, now) {
  const id = matchTrigger(parsedLine, config.triggerPrefix);
  if (!id) return null;

  const command = config.commands.find((c) => c.id.toLowerCase() === id);
  if (!command) {
    return { skip: true, reason: `unknown sound id "${id}" from ${parsedLine.sender}` };
  }

  if (command.officerOnly && !isOfficerAllowed(config.officers, parsedLine.sender)) {
    return {
      skip: true,
      reason: `${parsedLine.sender} is not allowed to play officer-only "${command.id}"`,
    };
  }

  const secondsLeft = secondsUntilReady(
    cooldownState,
    command.id,
    command.cooldownSec,
    config.globalCooldownSec,
    now,
  );
  if (secondsLeft > 0) {
    return { skip: true, reason: `"${command.id}" is on cooldown for ${Math.ceil(secondsLeft)}s` };
  }

  return { play: command, sender: parsedLine.sender };
}
