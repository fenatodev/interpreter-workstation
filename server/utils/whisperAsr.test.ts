import { afterEach, describe, expect, test } from 'bun:test';
import os from 'node:os';
import path from 'node:path';
import { chmod, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { transcribeWavWithWhisper } from './whisperAsr';

const originalEnv = { ...process.env };

afterEach(() => {
  process.env = { ...originalEnv };
});

describe('transcribeWavWithWhisper', () => {
  test('runs configured whisper CLI and normalizes transcript text', async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), 'whisper-asr-test-'));
    try {
      const binaryPath = path.join(root, 'whisper-cli');
      const modelPath = path.join(root, 'model.bin');
      await writeFile(binaryPath, '#!/bin/sh\nprintf "  Qual a temperatura agora em Taubaté?  \\n"\n');
      await chmod(binaryPath, 0o755);
      await writeFile(modelPath, 'fake-model');

      process.env.WHISPER_SERVER_URL = 'disabled';
      process.env.WHISPER_CPP_BIN = binaryPath;
      process.env.WHISPER_CPP_MODEL = modelPath;
      process.env.WHISPER_CPP_LANGUAGE = 'pt';

      const text = await transcribeWavWithWhisper(Buffer.from('fake-wav'));
      expect(text).toBe('Qual a temperatura agora em Taubaté?');
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
