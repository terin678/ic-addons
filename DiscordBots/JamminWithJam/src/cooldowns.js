/**
 * Cooldown tracking, pure and injected -- state is a plain object the caller
 * owns, and every function here takes the clock as an argument instead of
 * reading it. That is what makes secondsUntilReady testable without a timer.
 *
 * There are two cooldowns at once, and the longer one wins: a per-command one
 * (so "airhorn" spammed by one person is throttled) and one global across
 * every command (so two different players cannot chain two different sounds
 * back to back). The addon enforces a cooldown of its own, but only for one
 * character at a time -- this is the one that sees everybody.
 */

export function createCooldownState() {
  return { lastFiredAt: {}, lastAnyFiredAt: 0 };
}

export function secondsUntilReady(state, commandId, cooldownSec, globalCooldownSec, now) {
  const perCommandMs = (state.lastFiredAt[commandId] ?? 0) + cooldownSec * 1000 - now;
  const globalMs = state.lastAnyFiredAt + globalCooldownSec * 1000 - now;
  const ms = Math.max(0, perCommandMs, globalMs);
  return ms / 1000;
}

export function recordFire(state, commandId, now) {
  state.lastFiredAt[commandId] = now;
  state.lastAnyFiredAt = now;
}
