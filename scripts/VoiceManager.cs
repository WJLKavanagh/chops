using Godot;
using System;
using Vosk;
using NAudio.Wave;
using System.Text.Json;
using System.Linq;

public partial class VoiceManager : Node
{
	// Define signals for GDScript to connect to
	[Signal] public delegate void PhraseRecognisedEventHandler(string phrase);
	[Signal] public delegate void PartialPhraseRecognisedEventHandler(string phrase);
	[Signal] public delegate void StatusChangedEventHandler(bool isListening);

	[Export] public string ModelPath = "res://vosk/vosk-model-en-us-0.22-lgraph";
	[Export] public bool LogRecognitionResults = true;
	[Export] public int MicDeviceNumber = 0; 

	private Model _model;
	private VoskRecognizer _recognizer;
	private WaveInEvent _waveIn;
	
	private bool _isRecording = false;
	private string _lastLoggedPartial = string.Empty;
	private string[] _currentGrammar = Array.Empty<string>();

	public override void _Ready()
	{
		string globalModelPath = ProjectSettings.GlobalizePath(ModelPath);
		Vosk.Vosk.SetLogLevel(0);
		
		GD.Print($"Loading Vosk model from: {globalModelPath}");
		_model = new Model(globalModelPath);
		
		// Initialise with open dictation (empty grammar string array fallback)
		SetGrammar(Array.Empty<string>());
		
		_waveIn = new WaveInEvent
		{
			DeviceNumber = MicDeviceNumber,
			WaveFormat = new WaveFormat(16000, 1)
		};
		_waveIn.DataAvailable += OnAudioDataAvailable;
	}

	// Called by GDScript to restrict what Vosk listens for
	public void SetGrammar(string[] phrases)
	{
		_currentGrammar = phrases;
		_recognizer?.Dispose();
		
		if (phrases == null || phrases.Length == 0)
		{
			// Open dictation mode
			_recognizer = new VoskRecognizer(_model, 16000.0f);
		}
		else
		{
			// Restricted grammar mode. [unk] is required by Vosk to handle out-of-grammar noise
			string grammarJson = JsonSerializer.Serialize(phrases.Concat(new[] { "[unk]" }));
			_recognizer = new VoskRecognizer(_model, 16000.0f, grammarJson);
		}
		
		_recognizer.SetWords(true);
		_recognizer.SetPartialWords(true);
		GD.Print("VoiceManager: Recogniser grammar updated.");
	}

	public void StartListening()
	{
		if (_isRecording) return;
		
		_isRecording = true;
		_waveIn.StartRecording();
		EmitSignal(SignalName.StatusChanged, true);
		GD.Print("VoiceManager: Started listening.");
	}

	public void StopListening()
	{
		if (!_isRecording) return;
		
		_isRecording = false;
		_waveIn.StopRecording();
		EmitSignal(SignalName.StatusChanged, false);
		GD.Print("VoiceManager: Stopped listening.");
	}

	private void OnAudioDataAvailable(object sender, WaveInEventArgs e)
	{
		if (_recognizer.AcceptWaveform(e.Buffer, e.BytesRecorded))
		{
			CallDeferred(nameof(ProcessRecognitionResult), _recognizer.Result(), true);
		}
		else
		{
			CallDeferred(nameof(ProcessRecognitionResult), _recognizer.PartialResult(), false);
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
		if (_waveIn != null)
		{
			_waveIn.StopRecording();
			_waveIn.Dispose();
		}
		_recognizer?.Dispose();
		_model?.Dispose();
	}
}
