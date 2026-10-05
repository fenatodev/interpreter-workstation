import { beforeEach, describe, expect, mock, test } from 'bun:test';

import { QwenStreamingCaptureSession, VoiceCaptureSession } from './voiceCapture';

class FakeAudioNode {
  connect(): void {}
  disconnect(): void {}
}

class FakeGainNode extends FakeAudioNode {
  gain = { value: 1 };
}

class FakeAnalyserNode extends FakeAudioNode {
  fftSize = 0;
  smoothingTimeConstant = 0;

  getFloatTimeDomainData(samples: Float32Array): void {
    samples.fill(0);
  }
}

class FakeAudioContext {
  readonly destination = {};
  readonly sampleRate = 48000;

  async resume(): Promise<void> {}
  createMediaStreamSource(): FakeAudioNode { return new FakeAudioNode(); }
  createAnalyser(): FakeAnalyserNode { return new FakeAnalyserNode(); }
  createScriptProcessor(): FakeAudioNode & { onaudioprocess: ((event: AudioProcessingEvent) => void) | null } {
    return {
      onaudioprocess: null,
      connect(): void {},
      disconnect(): void {},
    };
  }
  createGain(): FakeGainNode { return new FakeGainNode(); }
  async close(): Promise<void> {}
}

const getUserMediaMock = mock(async () => ({
  getTracks: () => [{ stop() {} }],
}) as unknown as MediaStream);

describe('voice capture microphone startup', () => {
  beforeEach(() => {
    getUserMediaMock.mockClear();
    globalThis.navigator = {
      mediaDevices: {
        getUserMedia: getUserMediaMock,
      },
    } as Navigator;
    globalThis.AudioContext = FakeAudioContext as unknown as typeof AudioContext;
  });

  test('starts conversational capture with an unconstrained audio request', async () => {
    const session = new VoiceCaptureSession({
      onUtterance: () => {},
    });

    await session.start();
    session.stop();

    expect(getUserMediaMock).toHaveBeenCalledTimes(1);
    expect(getUserMediaMock).toHaveBeenCalledWith({ audio: true });
  });

  test('starts streaming capture with an unconstrained audio request', async () => {
    const session = new QwenStreamingCaptureSession({
      onPcmChunk: () => {},
    });

    await session.start();
    session.stop();

    expect(getUserMediaMock).toHaveBeenCalledTimes(1);
    expect(getUserMediaMock).toHaveBeenCalledWith({ audio: true });
  });

  test('manual push-to-talk capture emits one WAV only after release', async () => {
    const utterances: Blob[] = [];
    const session = new VoiceCaptureSession({
      manualOnly: true,
      onUtterance: async (wavBlob) => {
        utterances.push(wavBlob);
      },
    });

    await session.start();
    session.beginManualUtterance();

    const samples = new Float32Array(4800);
    samples.fill(0.25);
    const internal = session as unknown as {
      handleAudioProcess(event: AudioProcessingEvent): void;
    };
    internal.handleAudioProcess({
      inputBuffer: {
        getChannelData: () => samples,
      },
    } as unknown as AudioProcessingEvent);

    expect(utterances).toHaveLength(0);
    await session.finishManualUtterance();
    expect(utterances).toHaveLength(1);
    expect(utterances[0]?.type).toBe('audio/wav');
    expect((utterances[0]?.size ?? 0) > 44).toBe(true);

    session.stop();
  });
});
