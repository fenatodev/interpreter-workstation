import { act, renderHook, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

const ipcMocks = vi.hoisted(() => {
  let playbackListener: ((event: any) => void) | null = null;
  const speak = vi.fn(async (request: any) => {
    playbackListener?.({
      audioBase64: 'AAAA',
      mimeType: 'audio/wav',
      text: request.text,
      source: request.source,
      messageId: request.messageId,
      sentenceIndex: request.sentenceIndex,
    });
    return { success: true };
  });

  return {
    tts: {
      speak,
      onPlaybackRequested: vi.fn((listener: (event: any) => void) => {
        playbackListener = listener;
        return () => {
          playbackListener = null;
        };
      }),
    },
    reset() {
      speak.mockClear();
      playbackListener = null;
    },
  };
});

vi.mock('../../src/ipc', () => ({
  tts: ipcMocks.tts,
}));

import { useTtsPlayback } from './useTtsPlayback';

class FakeAudio {
  static instances: FakeAudio[] = [];

  src: string;
  onended: (() => void) | null = null;
  onerror: (() => void) | null = null;
  play = vi.fn(async () => undefined);
  pause = vi.fn();
  removeAttribute = vi.fn();

  constructor(src: string) {
    this.src = src;
    FakeAudio.instances.push(this);
  }
}

describe('useTtsPlayback', () => {
  beforeEach(() => {
    ipcMocks.reset();
    FakeAudio.instances = [];
    vi.stubGlobal('Audio', FakeAudio);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('prefetches the next sentence while the current audio is still playing', async () => {
    const { unmount } = renderHook(() => useTtsPlayback());

    act(() => {
      window.dispatchEvent(new CustomEvent('assistant-tts:enqueue-sentence', {
        detail: {
          text: 'Primeira frase.',
          messageId: 'msg-1',
          sentenceIndex: 0,
          source: 'assistant-auto',
        },
      }));
      window.dispatchEvent(new CustomEvent('assistant-tts:enqueue-sentence', {
        detail: {
          text: 'Segunda frase.',
          messageId: 'msg-1',
          sentenceIndex: 1,
          source: 'assistant-auto',
        },
      }));
    });

    await waitFor(() => {
      expect(ipcMocks.tts.speak).toHaveBeenCalledTimes(2);
    });

    expect(FakeAudio.instances).toHaveLength(1);
    expect(FakeAudio.instances[0]?.play).toHaveBeenCalledTimes(1);

    act(() => {
      FakeAudio.instances[0]?.onended?.();
    });

    await waitFor(() => {
      expect(FakeAudio.instances).toHaveLength(2);
    });
    expect(FakeAudio.instances[1]?.play).toHaveBeenCalledTimes(1);

    unmount();
  });
});
