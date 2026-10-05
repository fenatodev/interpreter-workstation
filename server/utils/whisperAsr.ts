import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';

const DEFAULT_WHISPER_SERVER_URL = 'http://127.0.0.1:1264/inference';
const DEFAULT_WHISPER_BIN = '/mnt/infra/apps/whisper.cpp/build-vulkan/bin/whisper-cli';
const DEFAULT_WHISPER_MODEL = '/mnt/infra/apps/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin';
const DEFAULT_LANGUAGE = 'pt';
const DEFAULT_THREADS = 8;
const DEFAULT_BEAM_SIZE = 5;
const SERVER_TRANSCRIBE_TIMEOUT_MS = 30_000;
const CLI_TRANSCRIBE_TIMEOUT_MS = 120_000;

function resolvePositiveInteger(raw: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(raw ?? '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function normalizeWhisperTranscript(stdout: string): string {
  return stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function transcribeViaWhisperServer(
  wavBuffer: Buffer,
  serverUrl: string,
  language: string,
): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), SERVER_TRANSCRIBE_TIMEOUT_MS);
  try {
    const form = new FormData();
    form.append(
      'file',
      new Blob([new Uint8Array(wavBuffer)], { type: 'audio/wav' }),
      'utterance.wav',
    );
    form.append('response_format', 'json');
    form.append('language', language);

    const response = await fetch(serverUrl, {
      method: 'POST',
      body: form,
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`Whisper server returned HTTP ${response.status}`);
    }
    const payload = await response.json() as { text?: unknown };
    if (typeof payload.text !== 'string') {
      throw new Error('Whisper server response missing transcript text');
    }
    return normalizeWhisperTranscript(payload.text);
  } finally {
    clearTimeout(timeout);
  }
}

export async function transcribeWavWithWhisper(wavBuffer: Buffer): Promise<string> {
  const configuredServerUrl = process.env.WHISPER_SERVER_URL?.trim();
  const serverUrl = configuredServerUrl === 'disabled'
    ? ''
    : (configuredServerUrl || DEFAULT_WHISPER_SERVER_URL);
  const binaryPath = process.env.WHISPER_CPP_BIN?.trim() || DEFAULT_WHISPER_BIN;
  const modelPath = process.env.WHISPER_CPP_MODEL?.trim() || DEFAULT_WHISPER_MODEL;
  const language = process.env.WHISPER_CPP_LANGUAGE?.trim() || DEFAULT_LANGUAGE;
  const threads = resolvePositiveInteger(process.env.WHISPER_CPP_THREADS, DEFAULT_THREADS);
  const beamSize = resolvePositiveInteger(process.env.WHISPER_CPP_BEAM_SIZE, DEFAULT_BEAM_SIZE);

  if (serverUrl) {
    try {
      return await transcribeViaWhisperServer(wavBuffer, serverUrl, language);
    } catch (error) {
      console.warn('[WhisperASR] Local server unavailable; falling back to CLI.', error);
    }
  }

  if (!fs.existsSync(binaryPath)) {
    throw new Error(`Whisper runtime not found: ${binaryPath}`);
  }
  if (!fs.existsSync(modelPath)) {
    throw new Error(`Whisper model not found: ${modelPath}`);
  }

  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'interpreter-whisper-'));
  const wavPath = path.join(tempDir, 'utterance.wav');
  await writeFile(wavPath, wavBuffer);

  try {
    const args = [
      '-m', modelPath,
      '-f', wavPath,
      '-l', language,
      '-nt',
      '-np',
      '-t', String(threads),
      '-bs', String(beamSize),
    ];

    const child = spawn(binaryPath, args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: process.env,
    });

    let stdout = '';
    let stderr = '';
    let timedOut = false;

    child.stdout.on('data', (chunk: Buffer | string) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk: Buffer | string) => {
      stderr += chunk.toString();
    });

    const exitCode = await new Promise<number>((resolve, reject) => {
      const timeout = setTimeout(() => {
        timedOut = true;
        child.kill('SIGKILL');
      }, CLI_TRANSCRIBE_TIMEOUT_MS);

      child.on('error', (error) => {
        clearTimeout(timeout);
        reject(error);
      });
      child.on('close', (code) => {
        clearTimeout(timeout);
        resolve(typeof code === 'number' ? code : 1);
      });
    });

    if (timedOut) {
      throw new Error('Whisper transcription timed out');
    }
    if (exitCode !== 0) {
      throw new Error(stderr.trim() || stdout.trim() || `Whisper exited with code ${exitCode}`);
    }

    return normalizeWhisperTranscript(stdout);
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}
