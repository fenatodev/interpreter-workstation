import { useCallback, useEffect, useRef } from 'react';
import { tts as ttsIpc } from '../../src/ipc';
import type { TtsPlaybackRequestedEvent } from '../../electron/ipc/registry';

const ASSISTANT_TTS_ENQUEUE_EVENT = 'assistant-tts:enqueue-sentence';
const ASSISTANT_TTS_STOP_EVENT = 'assistant-tts:stop';
const ASSISTANT_TTS_MESSAGE_SPEAKING_EVENT = 'assistant-tts:message-speaking';
const ASSISTANT_TTS_PLAYBACK_STATE_EVENT = 'assistant-tts:playback-state';

interface EnqueuedSentence {
  text: string;
  messageId: string;
  sentenceIndex: number;
  source: 'assistant-auto' | 'manual';
}

/**
 * Singleton hook that wires the TTS playback pipeline:
 *   sentence queue -> synthesis queue -> ready-audio queue -> Audio playback
 *
 * Synthesis intentionally runs ahead of playback. With a faster-than-real-time
 * local TTS model this lets the next sentence become ready while the current
 * sentence is still playing, avoiding a synthesis-sized pause between them.
 *
 * Also handles standalone playback from the speak_text tool and settings previews
 * (audio arrives via onPlaybackRequested without a preceding enqueue event).
 *
 * Mount this exactly once (e.g. in PersistentLayer).
 */
export function useTtsPlayback(): void {
  "use no memo";

  const queueRef = useRef<EnqueuedSentence[]>([]);
  const readyAudioQueueRef = useRef<TtsPlaybackRequestedEvent[]>([]);
  const isProcessingRef = useRef(false);
  const currentAudioRef = useRef<HTMLAudioElement | null>(null);
  const stoppedRef = useRef(false);

  const dispatchIdleState = useCallback(() => {
    window.dispatchEvent(
      new CustomEvent(ASSISTANT_TTS_PLAYBACK_STATE_EVENT, {
        detail: { isSpeaking: false },
      }),
    );
    window.dispatchEvent(
      new CustomEvent(ASSISTANT_TTS_MESSAGE_SPEAKING_EVENT, {
        detail: { messageId: null, sentenceIndex: null, text: null },
      }),
    );
  }, []);

  const playNextReadyAudio = useCallback(() => {
    if (stoppedRef.current || currentAudioRef.current) return;

    const event = readyAudioQueueRef.current.shift();
    if (!event) {
      if (!isProcessingRef.current && queueRef.current.length === 0) {
        dispatchIdleState();
      }
      return;
    }

    window.dispatchEvent(
      new CustomEvent(ASSISTANT_TTS_PLAYBACK_STATE_EVENT, {
        detail: { isSpeaking: true },
      }),
    );
    window.dispatchEvent(
      new CustomEvent(ASSISTANT_TTS_MESSAGE_SPEAKING_EVENT, {
        detail: {
          messageId: event.messageId ?? null,
          sentenceIndex: event.sentenceIndex ?? null,
          text: event.text ?? null,
        },
      }),
    );

    const audio = new Audio(`data:${event.mimeType};base64,${event.audioBase64}`);
    currentAudioRef.current = audio;

    const finish = () => {
      if (currentAudioRef.current !== audio) return;
      currentAudioRef.current = null;
      playNextReadyAudio();
    };

    audio.onended = finish;
    audio.onerror = finish;
    audio.play().catch(finish);
  }, [dispatchIdleState]);

  const stopPlayback = useCallback(() => {
    stoppedRef.current = true;
    queueRef.current = [];
    readyAudioQueueRef.current = [];

    const audio = currentAudioRef.current;
    if (audio) {
      audio.pause();
      audio.removeAttribute('src');
      currentAudioRef.current = null;
    }

    dispatchIdleState();
  }, [dispatchIdleState]);

  // Server-side synthesis broadcasts each completed WAV. Queue the WAV instead
  // of playing it immediately so multiple prefetched sentences remain ordered.
  useEffect(() => {
    const unsubscribe = ttsIpc.onPlaybackRequested((event: TtsPlaybackRequestedEvent) => {
      // A stop can race with a synthesis already running. That synthesis emits
      // its broadcast before its IPC promise settles, so drop it while the old
      // queue loop is still unwinding.
      if (stoppedRef.current && isProcessingRef.current) {
        return;
      }

      // Standalone previews/tool playback are allowed after a previous stop.
      stoppedRef.current = false;
      readyAudioQueueRef.current.push(event);
      playNextReadyAudio();
    });

    return unsubscribe;
  }, [playNextReadyAudio]);

  // Drain synthesis independently from playback. Once a WAV is broadcast, move
  // immediately to the next sentence; audio playback continues from its own queue.
  const processQueue = useCallback(async () => {
    if (isProcessingRef.current) return;
    isProcessingRef.current = true;
    stoppedRef.current = false;

    window.dispatchEvent(
      new CustomEvent(ASSISTANT_TTS_PLAYBACK_STATE_EVENT, {
        detail: { isSpeaking: true },
      }),
    );

    while (queueRef.current.length > 0 && !stoppedRef.current) {
      const sentence = queueRef.current.shift()!;

      try {
        await ttsIpc.speak({
          text: sentence.text,
          play: true,
          source: sentence.source,
          messageId: sentence.messageId,
          sentenceIndex: sentence.sentenceIndex,
        });
      } catch {
        // Skip a failed sentence and keep the remainder of the response flowing.
      }
    }

    isProcessingRef.current = false;

    if (
      !stoppedRef.current
      && !currentAudioRef.current
      && readyAudioQueueRef.current.length === 0
      && queueRef.current.length === 0
    ) {
      dispatchIdleState();
    }

    // Pick up sentences enqueued during the narrow window while this loop was
    // winding down.
    if (queueRef.current.length > 0 && !stoppedRef.current) {
      void processQueue();
    }
  }, [dispatchIdleState]);

  useEffect(() => {
    const handleEnqueue = (event: Event) => {
      const detail = (event as CustomEvent<EnqueuedSentence>).detail;
      if (!detail?.text) return;

      queueRef.current.push({
        text: detail.text,
        messageId: detail.messageId,
        sentenceIndex: detail.sentenceIndex,
        source: detail.source ?? 'manual',
      });

      void processQueue();
    };

    const handleStop = () => {
      stopPlayback();
    };

    window.addEventListener(ASSISTANT_TTS_ENQUEUE_EVENT, handleEnqueue as EventListener);
    window.addEventListener(ASSISTANT_TTS_STOP_EVENT, handleStop);

    return () => {
      window.removeEventListener(ASSISTANT_TTS_ENQUEUE_EVENT, handleEnqueue as EventListener);
      window.removeEventListener(ASSISTANT_TTS_STOP_EVENT, handleStop);
      stopPlayback();
    };
  }, [processQueue, stopPlayback]);
}
