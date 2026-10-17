using Godot;
using System;
using Vosk;
using NAudio.Wave;
using System.Text.Json;
using System.Linq;

public partial class VoiceManager : Node
{
	private const string RecordingStartSoundPath = "res://assets/audio/sfx/rec_start.wav";
	private const string RecordingEndSoundPath = "res://assets/audio/sfx/rec_end.wav";

	// Define signals for GDScript to connect to
	[Signal] public delegate void PhraseRecognisedEventHandler(string phrase);
	[Signal] public delegate void PhraseAlternativesRecognisedEventHandler(string[] phrases);
	[Signal] public delegate void PartialPhraseRecognisedEventHandler(string phrase);
	[Signal] public delegate void StatusChangedEventHandler(bool isListening);

	[Export] public string ModelPath = "res://vosk/vosk-model-en-us-0.22-lgraph";
	[Export] public bool LogRecognitionResults = true;
	[Export] public int MicDeviceNumber = 0; 

	private Model _model;
	private VoskRecognizer _recognizer;
	private readonly object _recognizerLock = new();
	private WaveInEvent _waveIn;
	private AudioStreamPlayer _recordingStartPlayer;
	private AudioStreamPlayer _recordingEndPlayer;
	
	private bool _isRecording = false;
	private bool _listeningEnabled = true;
	private bool _isFocused = true;
	private bool _isDebugBuild = false;
	private string _lastLoggedPartial = string.Empty;
	private string[] _currentGrammar = Array.Empty<string>();

	public override void _Ready()
	{
		// Detect if running from the Godot editor/debug build
		_isDebugBuild = OS.IsDebugBuild();

		_recordingStartPlayer = CreateRecordingCuePlayer(RecordingStartSoundPath);
		_recordingEndPlayer = CreateRecordingCuePlayer(RecordingEndSoundPath);

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

	private AudioStreamPlayer CreateRecordingCuePlayer(string resourcePath)
	{
		AudioStream stream = GD.Load<AudioStream>(resourcePath);
		if (stream == null)
		{
			GD.PushError($"VoiceManager: Could not load recording cue at {resourcePath}.");
			return null;
		}

		var player = new AudioStreamPlayer
		{
			Stream = stream
		};
		AddChild(player);
		return player;
	}

	// Capture OS window focus changes
	public override void _Notification(int what)
	{
		if (what == NotificationApplicationFocusIn)
		{
			_isFocused = true;
			CallDeferred(nameof(ResumeListeningIfAllowed));
		}
		else if (what == NotificationApplicationFocusOut)
		{
			_isFocused = false;
			if (_isDebugBuild)
			{
				StopListening();
			}
		}
	}

	private void ResumeListeningIfAllowed()
	{
		if (!_isDebugBuild || !_isFocused || !_listeningEnabled || IsTtsSpeaking())
		{
			return;
		}

		StartListening();
	}

	private bool IsTtsSpeaking()
	{
		Node ttsManager = GetNodeOrNull<Node>("/root/TTS_Manager");
		return ttsManager != null && ttsManager.Get("is_speaking").AsBool();
	}

	// Called by GDScript to restrict what Vosk listens for
	//UMMM okay, let's see, if the grammar is same as before IGNORE whatever command it is, should stop the roundel freeze mayhaps as it shouldn't spike CPU. Then I think just vosk in background thread too? Will this fuck up the network ver, it shouldn't I don't think but double check after.  
	public void SetGrammar(string[] phrases)
	{
		string[] grammarPhrases = phrases ?? Array.Empty<string>();
		
		if (_currentGrammar.SequenceEqual(grammarPhrases))
		{
			return; //Caps, uncaps, caps, noodles
		}
		
		//OMFG, Might help if I actually save the updated grammar before rebuilding it lmao
		_currentGrammar = grammarPhrases;
		
		//Background thread start
		System.Threading.Tasks.Task.Run(() =>
		{
			VoskRecognizer replacement;
			
			if (grammarPhrases.Length == 0)
			{
				replacement = new VoskRecognizer(_model, 16000.0f);
			}
			else
			{
				// Restricted grammar mode. [unk] handles out-of-grammar noise.
				string grammarJson = JsonSerializer.Serialize(grammarPhrases.Concat(new[] { "[unk]" }));
				replacement = new VoskRecognizer(_model, 16000.0f, grammarJson);
			}
			
			replacement.SetWords(true);
			replacement.SetPartialWords(true);
			replacement.SetMaxAlternatives(3);
			
			VoskRecognizer previous; //Pretty much same as it used to be.
			
			//Okay, now locking the thread for a milisecond to get the pointer swapped. I'll just keep the old spelling from here before.
			lock (_recognizerLock)
			{
				previous = _recognizer;
				_recognizer = replacement; //American spelling for Vosk continuity is throwing me so much
			}
			
			//FOUND OUT I NEED THIS, gets rid of the old recogniser outside of the lock so the audio thread never is hanging around
			previous?.Dispose();
			
			CallDeferred(nameof(PrintGrammarUpdated));
		});
	}
		

	private void PrintGrammarUpdated() //Does as it says on the tin
	{
			GD.Print("Voice Manager: Recogniser of grammar updated");
	}

	public void StartListening()
	{
		if (!_listeningEnabled || (_isDebugBuild && !_isFocused))
		{
			return;
		}

		if (_isRecording) return;
		
		_isRecording = true;
		_waveIn.StartRecording();
		//_recordingStartPlayer?.Play(); // EARCON removed because it sucks.
		EmitSignal(SignalName.StatusChanged, true);
		GD.Print("VoiceManager: Started listening.");
	}

	public void StopListening()
	{
		if (!_isRecording) return;
		
		_isRecording = false;
		_waveIn.StopRecording();
		//_recordingEndPlayer?.Play();	// gross ding removed
		EmitSignal(SignalName.StatusChanged, false);
		GD.Print("VoiceManager: Stopped listening.");
	}

	public void SetListeningEnabled(bool enabled)
	{
		_listeningEnabled = enabled;
		if (!enabled)
		{
			StopListening();
		}
	}

	private void OnAudioDataAvailable(object sender, WaveInEventArgs e)
	{
		bool isFinal;
		string result;
		lock (_recognizerLock)
		{
			if (_recognizer == null)
			{
				return;
			}

			isFinal = _recognizer.AcceptWaveform(e.Buffer, e.BytesRecorded);
			result = isFinal ? _recognizer.Result() : _recognizer.PartialResult();
		}

		CallDeferred(nameof(ProcessRecognitionResult), result, isFinal);
	}
	
	private void ProcessRecognitionResult(string jsonResult, bool isFinal)
	{
		// Drop input if running two instances in the editor and this window lacks focus
		if (_isDebugBuild && !_isFocused) return;

		try
		{
			using JsonDocument doc = JsonDocument.Parse(jsonResult);
			string spokenText = string.Empty; //Start to GB fixes, I'll keep formatting the same, capital/lowercase
			
			if (isFinal)//Is Vosk using the alternatives array format check
			{
					if (doc.RootElement.TryGetProperty("alternatives", out JsonElement alternatives) && alternatives.GetArrayLength() > 0)
					{
							if (alternatives[0].TryGetProperty("text", out JsonElement altText)) //Grabbing whatever text from the highest confidence alternative/partial
							{
								spokenText = altText.GetString()?.Trim().ToLower() ?? string.Empty;
							} 
					}
					
					//if not, fallback to standard form/root text yay!
					else if (doc.RootElement.TryGetProperty("text", out JsonElement textElement))
					{
						spokenText = textElement.GetString()?.Trim().ToLower() ?? string.Empty;
					}
			}
			
			else
			{
				if (doc.RootElement.TryGetProperty("partial", out JsonElement partialElement))
				{
					spokenText = partialElement.GetString()?.Trim().ToLower() ?? string.Empty;
				}
			}
			
			
	

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
				EmitSignal(SignalName.PhraseAlternativesRecognised, GetAlternatives(doc.RootElement, spokenText));
				EmitSignal(SignalName.PhraseRecognised, spokenText);
			}
			else
			{
				EmitSignal(SignalName.PartialPhraseRecognised, spokenText);
			}
			
		}
		catch (JsonException exception)
		{
			GD.PushWarning($"Could not parse Vosk recognition result: {exception.Message}");
		}
	}

	private static string[] GetAlternatives(JsonElement root, string bestPhrase)
	{
		var phrases = new System.Collections.Generic.List<string> { bestPhrase };
		if (root.TryGetProperty("alternatives", out JsonElement alternatives) &&
			alternatives.ValueKind == JsonValueKind.Array)
		{
			foreach (JsonElement alternative in alternatives.EnumerateArray())
			{
				if (!alternative.TryGetProperty("text", out JsonElement text))
				{
					continue;
				}

				string phrase = text.GetString()?.Trim().ToLowerInvariant() ?? string.Empty;
				if (!string.IsNullOrWhiteSpace(phrase) && !phrases.Contains(phrase))
				{
					phrases.Add(phrase);
				}
			}
		}

		return phrases.ToArray();
	}

	public override void _ExitTree()
	{
		if (_waveIn != null)
		{
			_waveIn.StopRecording();
			_waveIn.Dispose();
		}
		lock (_recognizerLock)
		{
			_recognizer?.Dispose();
			_recognizer = null;
		}
		_model?.Dispose();
	}
}
