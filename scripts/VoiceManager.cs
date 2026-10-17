using Godot;
using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using Vosk;

public partial class VoiceManager : Node
{
	// Define signals for GDScript to connect to
	[Signal] public delegate void PhraseRecognisedEventHandler(string phrase);
	[Signal] public delegate void PartialPhraseRecognisedEventHandler(string phrase);
	[Signal] public delegate void StatusChangedEventHandler(bool isListening);

	private const int VoskSampleRate = 16000;
	private const string CaptureBusName = "MicCapture";

	[Export] public string ModelPath = "res://vosk/vosk-model-en-us-0.22-lgraph";
	[Export] public bool LogRecognitionResults = true;

	// Index into the device list printed at startup. -1 = system default mic.
	[Export] public int MicDeviceNumber = -1;

	// macOS only: where libvosk.dylib lives (next to the model by default)
	[Export] public string VoskLibraryPath = "res://vosk/libvosk.dylib";

	private Model _model;
	private VoskRecognizer _recognizer;
	private readonly object _recognizerLock = new();

	// Godot mic capture (replaces NAudio's WaveInEvent, which is Windows-only)
	private AudioStreamPlayer _mic;
	private AudioEffectCapture _capture;
	private double _resampleStep;   // mix rate / 16000
	private double _phase;          // source samples counted toward the next output sample
	private double _sum;
	private int _count;

	// Vosk runs on its own thread so the large model never stalls the game loop
	private readonly BlockingCollection<byte[]> _audioQueue = new();
	private Thread _worker;

	private bool _isRecording = false;
	private string _lastLoggedPartial = string.Empty;
	private string[] _currentGrammar = Array.Empty<string>();

	public override void _Ready()
	{
		if (!ProjectSettings.GetSetting("audio/driver/enable_input", false).AsBool())
		{
			GD.PushWarning("Microphone input is disabled. Enable Project Settings > Audio > Driver > Enable Input and restart the editor.");
		}

		// Print available microphones
		string[] devices = AudioServer.GetInputDeviceList();
		GD.Print("--- Available Microphones ---");
		for (int i = 0; i < devices.Length; i++)
		{
			GD.Print($"Device {i}: {devices[i]}");
		}
		GD.Print("-----------------------------");

		if (MicDeviceNumber >= 0 && MicDeviceNumber < devices.Length)
		{
			AudioServer.InputDevice = devices[MicDeviceNumber];
			GD.Print($"Using microphone: {devices[MicDeviceNumber]}");
		}

		RegisterVoskNativeLibrary();

		string globalModelPath = ProjectSettings.GlobalizePath(ModelPath);
		Vosk.Vosk.SetLogLevel(0);

		GD.Print($"Loading Vosk model from: {globalModelPath}");
		_model = new Model(globalModelPath);

		// Initialise with open dictation unless a grammar was already set
		SetGrammar(_currentGrammar);

		SetupCapture();

		_worker = new Thread(RecognitionLoop) { IsBackground = true, Name = "VoskWorker" };
		_worker.Start();
	}

	// Godot's .NET host doesn't search the project folder for native libraries,
	// so tell .NET exactly where libvosk is. Must run before any Vosk call.
	private void RegisterVoskNativeLibrary()
	{
		if (!OperatingSystem.IsMacOS())
		{
			return; // the Vosk NuGet package already handles Windows/Linux
		}

		string libPath = ProjectSettings.GlobalizePath(VoskLibraryPath);
		if (!System.IO.File.Exists(libPath))
		{
			GD.PushError($"libvosk.dylib not found at: {libPath}");
			return;
		}

		try
		{
			NativeLibrary.SetDllImportResolver(typeof(Vosk.Vosk).Assembly,
				(name, assembly, searchPath) =>
					name == "libvosk" ? NativeLibrary.Load(libPath) : IntPtr.Zero);
			GD.Print($"Using libvosk from: {libPath}");
		}
		catch (InvalidOperationException)
		{
			// resolver was already registered for this assembly
		}
	}

	private void SetupCapture()
	{
		int bus = AudioServer.GetBusIndex(CaptureBusName);
		if (bus == -1)
		{
			AudioServer.AddBus();
			bus = AudioServer.BusCount - 1;
			AudioServer.SetBusName(bus, CaptureBusName);
			AudioServer.AddBusEffect(bus, new AudioEffectCapture(), 0);
			AudioServer.SetBusMute(bus, true); // capture only, no speaker feedback
		}

		_capture = (AudioEffectCapture)AudioServer.GetBusEffect(bus, 0);
		_resampleStep = AudioServer.GetMixRate() / VoskSampleRate;

		_mic = new AudioStreamPlayer
		{
			Stream = new AudioStreamMicrophone(),
			Bus = CaptureBusName
		};
		AddChild(_mic);
	}

	// Called by GDScript to restrict what Vosk listens for
	public void SetGrammar(string[] phrases)
	{
		_currentGrammar = phrases ?? Array.Empty<string>();

		if (_model == null)
		{
			return; // applied once the model has loaded in _Ready
		}

		VoskRecognizer next;
		if (_currentGrammar.Length == 0)
		{
			// Open dictation mode
			next = new VoskRecognizer(_model, (float)VoskSampleRate);
		}
		else
		{
			// Restricted grammar mode. [unk] is required by Vosk to handle out-of-grammar noise
			string grammarJson = JsonSerializer.Serialize(_currentGrammar.Concat(new[] { "[unk]" }));
			next = new VoskRecognizer(_model, (float)VoskSampleRate, grammarJson);
		}

		next.SetWords(true);
		next.SetPartialWords(true);

		// The worker thread uses the recognizer, so swap it under the lock
		lock (_recognizerLock)
		{
			_recognizer?.Dispose();
			_recognizer = next;
		}

		GD.Print("VoiceManager: Recogniser grammar updated.");
	}

	public void StartListening()
	{
		if (_isRecording) return;

		_isRecording = true;
		_phase = 0;
		_sum = 0;
		_count = 0;
		_capture.ClearBuffer();
		_mic.Play();
		EmitSignal(SignalName.StatusChanged, true);
		GD.Print("VoiceManager: Started listening.");
	}

	public void StopListening()
	{
		if (!_isRecording) return;

		_isRecording = false;
		_mic.Stop();
		_capture.ClearBuffer();
		while (_audioQueue.TryTake(out _)) { }
		EmitSignal(SignalName.StatusChanged, false);
		GD.Print("VoiceManager: Stopped listening.");
	}

	public override void _Process(double delta)
	{
		if (_isRecording)
		{
			DrainCapture();
		}
	}

	// Pull stereo float frames from Godot, downmix to mono, resample to 16 kHz, convert to 16-bit PCM.
	private void DrainCapture()
	{
		int frames = _capture.GetFramesAvailable();
		if (frames <= 0)
		{
			return;
		}

		Vector2[] src = _capture.GetBuffer(frames);
		var pcm = new byte[((int)(frames / _resampleStep) + 2) * 2];
		int n = 0;

		for (int i = 0; i < src.Length; i++)
		{
			_sum += (src[i].X + src[i].Y) * 0.5f;
			_count++;
			_phase += 1.0;

			if (_phase >= _resampleStep)
			{
				_phase -= _resampleStep;
				float mono = (float)(_sum / _count);
				_sum = 0;
				_count = 0;

				short s = (short)(Mathf.Clamp(mono, -1f, 1f) * short.MaxValue);
				pcm[n++] = (byte)(s & 0xFF);
				pcm[n++] = (byte)((s >> 8) & 0xFF);
			}
		}

		if (n > 0)
		{
			Array.Resize(ref pcm, n);
			_audioQueue.Add(pcm);
		}
	}

	private void RecognitionLoop()
	{
		foreach (byte[] chunk in _audioQueue.GetConsumingEnumerable())
		{
			string json;
			bool isFinal;

			lock (_recognizerLock)
			{
				if (_recognizer == null)
				{
					continue;
				}

				isFinal = _recognizer.AcceptWaveform(chunk, chunk.Length);
				json = isFinal ? _recognizer.Result() : _recognizer.PartialResult();
			}

			CallDeferred(nameof(ProcessRecognitionResult), json, isFinal);
		}
	}

	private void ProcessRecognitionResult(string jsonResult, bool isFinal)
	{
		try
		{
			using JsonDocument doc = JsonDocument.Parse(jsonResult);
			string searchKey = isFinal ? "text" : "partial";

			if (doc.RootElement.TryGetProperty(searchKey, out JsonElement textElement))
			{
				string spokenText = textElement.GetString()?.Trim().ToLower() ?? string.Empty;

				if (LogRecognitionResults && (isFinal || spokenText != _lastLoggedPartial))
				{
					GD.Print($"Vosk {(isFinal ? "final" : "partial")}: {spokenText}");
				}

				_lastLoggedPartial = isFinal ? string.Empty : spokenText;

				if (!_isRecording || string.IsNullOrWhiteSpace(spokenText)) return;

				// Ignore the unknown token
				if (spokenText.Contains("[unk]")) return;

				if (isFinal)
				{
					EmitSignal(SignalName.PhraseRecognised, spokenText);
				}
				else
				{
					EmitSignal(SignalName.PartialPhraseRecognised, spokenText);
				}
			}
		}
		catch (JsonException exception)
		{
			GD.PushWarning($"Could not parse Vosk recognition result: {exception.Message}");
		}
	}

	public override void _ExitTree()
	{
		_audioQueue.CompleteAdding();
		_worker?.Join(2000);

		lock (_recognizerLock)
		{
			_recognizer?.Dispose();
			_recognizer = null;
		}
		_model?.Dispose();
	}
}
