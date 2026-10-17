// DEPRECATED - use this only to check the vosk code. 
// scripts/VoiceManager.cs is the main script now.

using Godot;
using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using Vosk;

public partial class SpeechRecogniser : Control
{
	private const double BeatDurationSeconds = 2.0;
	private const int VoskSampleRate = 16000;
	private const string CaptureBusName = "MicCapture";

	private static readonly string[] RecognizedTerms = { "super move", "kick", "punch", "block", "duck" };
	private static readonly Regex RecognizedTermPattern = new(
		@"\b(?:" + string.Join("|", Array.ConvertAll(RecognizedTerms, term => Regex.Escape(term).Replace(" ", @"\s+"))) + @")\b",
		RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

	[Export] public string ModelPath = "res://vosk/vosk-model-en-us-0.22-lgraph";
	[Export] public bool LogRecognitionResults = true;

	// macOS only: where libvosk.dylib lives (next to the model by default)
	[Export] public string VoskLibraryPath = "res://vosk/libvosk.dylib";

	// Index into the device list printed at startup. -1 = system default mic.
	[Export] public int MicDeviceNumber = -1;

	private Model _model;
	private VoskRecognizer _recognizer;

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

	private Button _recordButton;
	private Label _outputLabel;

	private bool _isRecording = false;
	private double _beatElapsed;
	private int _beatNumber;
	private bool _moveAcceptedThisBeat;
	private string _lastLoggedPartial = string.Empty;

	public override void _Ready()
	{
		_recordButton = GetNode<Button>("Button");
		_outputLabel = GetNode<Label>("Label");
		_recordButton.Pressed += OnRecordButtonPressed;
		_outputLabel.Text = "Status: Ready.";

		if (!ProjectSettings.GetSetting("audio/driver/enable_input", false).AsBool())
		{
			GD.PushWarning("Microphone input is disabled. Enable Project Settings > Audio > Driver > Enable Input and restart the editor.");
		}

		// 1. Print available microphones to help you find your 4-channel mic
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

		// 2. Initialise Vosk
		RegisterVoskNativeLibrary();
		string globalModelPath = ProjectSettings.GlobalizePath(ModelPath);
		Vosk.Vosk.SetLogLevel(0);
		GD.Print($"Loading Vosk model from: {globalModelPath}");
		_model = new Model(globalModelPath);
		GD.Print("Vosk model loaded.");
		string grammar = JsonSerializer.Serialize(RecognizedTerms.Concat(new[] { "[unk]" }));
		GD.Print($"Vosk command grammar: {grammar}");
		_recognizer = new VoskRecognizer(_model, (float)VoskSampleRate, grammar);
		_recognizer.SetWords(true);
		_recognizer.SetPartialWords(true);
		GD.Print("Vosk recognizer ready at 16000 Hz.");

		// 3. Initialise Godot mic capture
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

	public override void _Process(double delta)
	{
		if (!_isRecording)
		{
			return;
		}

		DrainCapture();

		_beatElapsed += delta;
		while (_beatElapsed >= BeatDurationSeconds)
		{
			_beatElapsed -= BeatDurationSeconds;
			_beatNumber++;
			_moveAcceptedThisBeat = false;
			_outputLabel.Text = $"Beat {_beatNumber}: say a move";
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
			bool isFinal = _recognizer.AcceptWaveform(chunk, chunk.Length);

			// Final result triggers when you pause; partial updates while you speak
			string json = isFinal ? _recognizer.Result() : _recognizer.PartialResult();
			CallDeferred(nameof(ExtractAndDisplayText), json, isFinal);
		}
	}

	private void OnRecordButtonPressed()
	{
		_isRecording = !_isRecording;

		if (_isRecording)
		{
			_beatElapsed = 0;
			_beatNumber = 1;
			_moveAcceptedThisBeat = false;
			_phase = 0;
			_sum = 0;
			_count = 0;
			_recordButton.Text = "Stop Listening";
			_outputLabel.Text = $"Beat {_beatNumber}: say a move";
			_capture.ClearBuffer();
			_mic.Play();
		}
		else
		{
			_recordButton.Text = "Start Listening";
			_outputLabel.Text = "Status: Stopped.";
			_mic.Stop();
			_capture.ClearBuffer();
			while (_audioQueue.TryTake(out _)) { }
		}
	}

	private void ExtractAndDisplayText(string jsonResult, bool isFinal)
	{
		try
		{
			using JsonDocument doc = JsonDocument.Parse(jsonResult);
			string searchKey = isFinal ? "text" : "partial";

			if (doc.RootElement.TryGetProperty(searchKey, out JsonElement textElement))
			{
				string spokenText = textElement.GetString() ?? string.Empty;

				if (LogRecognitionResults && (isFinal || spokenText != _lastLoggedPartial))
				{
					GD.Print($"Vosk {(isFinal ? "final" : "partial")}: {jsonResult}");
				}

				_lastLoggedPartial = isFinal ? string.Empty : spokenText;

				if (!_isRecording || string.IsNullOrWhiteSpace(spokenText))
				{
					return;
				}

				var matches = RecognizedTermPattern.Matches(spokenText);
				if (!isFinal)
				{
					_outputLabel.Text = $"Beat {_beatNumber}: hearing {spokenText}...";
					return;
				}

				if (matches.Count == 0)
				{
					_outputLabel.Text = $"Beat {_beatNumber}: heard \"{spokenText}\" (no listed move)";
					return;
				}

				if (!_moveAcceptedThisBeat)
				{
					_moveAcceptedThisBeat = true;
					_outputLabel.Text = $"Beat {_beatNumber}: heard \"{spokenText}\"";
				}
				else
				{
					_outputLabel.Text = $"Beat {_beatNumber}: heard \"{spokenText}\" (move already used)";
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

		_recognizer?.Dispose();
		_model?.Dispose();
	}
}
