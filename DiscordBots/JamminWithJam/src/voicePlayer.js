import path from "node:path";
import {
  AudioPlayerStatus,
  VoiceConnectionStatus,
  createAudioPlayer,
  createAudioResource,
  entersState,
  joinVoiceChannel,
} from "@discordjs/voice";
import ffmpegPath from "ffmpeg-static";

if (ffmpegPath) {
  // prism-media (which @discordjs/voice uses to transcode arbitrary audio
  // files to Opus) looks for ffmpeg on PATH by default; this points it at
  // the binary ffmpeg-static already downloaded, so nobody running the bot
  // has to install ffmpeg separately.
  process.env.FFMPEG_PATH = ffmpegPath;
}

/**
 * Joins one voice channel and stays there, playing sound files one at a
 * time off an in-memory queue. There is no Discord-side command to start or
 * stop this -- it connects once at bot startup and reconnects on its own if
 * Discord drops it, the same way a music bot's connection is expected to
 * behave.
 */
export function createVoicePlayer({ soundsDir }) {
  const player = createAudioPlayer();
  const queue = [];
  let playing = false;
  let connection = null;

  function playNext() {
    if (playing || queue.length === 0) return;
    const file = queue.shift();
    playing = true;
    try {
      const resource = createAudioResource(path.join(soundsDir, file));
      player.play(resource);
    } catch (err) {
      playing = false;
      throw err;
    }
  }

  player.on(AudioPlayerStatus.Idle, () => {
    playing = false;
    playNext();
  });

  // A file that fails to decode (missing, corrupt) must not wedge every
  // sound queued behind it.
  player.on("error", (err) => {
    console.error("[voicePlayer] playback error:", err.message);
    playing = false;
    playNext();
  });

  return {
    async connect(voiceChannelId, guildId, adapterCreator) {
      connection = joinVoiceChannel({
        channelId: voiceChannelId,
        guildId,
        adapterCreator,
        selfDeaf: false,
      });
      connection.subscribe(player);

      connection.on(VoiceConnectionStatus.Disconnected, async () => {
        // Discord's own reconnect dance: a disconnect is ambiguous between
        // "moved channels" (recoverable) and "kicked" (not), so wait briefly
        // to see which state it settles into before giving up.
        try {
          await Promise.race([
            entersState(connection, VoiceConnectionStatus.Signalling, 5_000),
            entersState(connection, VoiceConnectionStatus.Connecting, 5_000),
          ]);
        } catch {
          connection.destroy();
        }
      });

      await entersState(connection, VoiceConnectionStatus.Ready, 20_000);
      return connection;
    },

    enqueue(file) {
      queue.push(file);
      playNext();
    },

    get queueLength() {
      return queue.length + (playing ? 1 : 0);
    },

    get connectionStatus() {
      return connection?.state.status ?? "not connected";
    },
  };
}
