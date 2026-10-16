using Godot;
using System;
using Vosk;
using NAudio.Wave;
using System.Text.Json;
using System.Text.RegularExpressions;

public partial class SpeechRecogniser : Control
{
	private const double BeatDurationSeconds = 2.0;
	private static readonly string[] RecognizedTerms = { "super move", "kick", "punch", "block", "duck" };
	private static readonly Regex RecognizedTermPattern = new(
		@"\b(?:" + string.Join("|", Array.ConvertAll(RecognizedTerms, term => Regex.Escape(term).Replace(" ", @"\s+"))) + @")\b",
		RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

	[Export] public string ModelPath = "res://vosk/vosk-model-en-us-0.22-lgraph";
	
	// the active mic
	[Export] public int MicDeviceNumber = 0; 
	
	private Model _model;
	private VoskRecognizer _recognizer;
	private WaveInEvent _waveIn; 	// a bit spicy, but it works.
	
	private Button _recordButton;
	private Label _outputLabel;
	
	private bool _isRecording = false;
	private double _beatElapsed;
	private int _beatNumber;
	private bool _moveAcceptedThisBeat;
	
	public override void _Ready()
	{
		_recordButton = GetNode<Button>("Button");
		_outputLabel = GetNode<Label>("Label");
		_recordButton.Pressed += OnRecordButtonPressed;
		_outputLabel.Text = "Status: Ready.";

		// 1. Print available microphones to help you find your 4-channel mic
		GD.Print("--- Available Microphones ---");
		for (int i = 0; i < WaveIn.DeviceCount; i++)
		{
			var caps = WaveIn.GetCapabilities(i);
			GD.Print($"Device {i}: {caps.ProductName}");
		}
		GD.Print("-----------------------------");
		
		// 2. Initialise Vosk
		string globalModelPath = ProjectSettings.GlobalizePath(ModelPath);
		Vosk.Vosk.SetLogLevel(-1);
		_model = new Model(globalModelPath);
		_recognizer = new VoskRecognizer(_model, 16000.0f);
		
		// 3. Initialise NAudio
		_waveIn = new WaveInEvent();
		_waveIn.DeviceNumber = MicDeviceNumber;
		_waveIn.WaveFormat = new WaveFormat(16000, 1); 
		_waveIn.DataAvailable += OnAudioDataAvailable;
	}

	public override void _Process(double delta)
	{
		if (!_isRecording)
		{
			return;
		}

		_beatElapsed += delta;
		while (_beatElapsed >= BeatDurationSeconds)
		{
			_beatElapsed -= BeatDurationSeconds;
			_beatNumber++;
			_moveAcceptedThisBeat = false;
			_outputLabel.Text = $"Beat {_beatNumber}: say a move";
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
			_recordButton.Text = "Stop Listening";
			_outputLabel.Text = $"Beat {_beatNumber}: say a move";
			_waveIn.StartRecording(); 
		}
		else
		{
			_recordButton.Text = "Start Listening";
			_outputLabel.Text = "Status: Stopped.";
			_waveIn.StopRecording(); 
		}
	}

	private void OnAudioDataAvailable(object sender, WaveInEventArgs e)
	{
		if (_recognizer.AcceptWaveform(e.Buffer, e.BytesRecorded))
		{
			// Final result (triggers when you pause/stop speaking)
			CallDeferred(nameof(ExtractAndDisplayText), _recognizer.Result(), true);
		}
		else
		{
			// Partial result (triggers instantly while you are speaking)
			CallDeferred(nameof(ExtractAndDisplayText), _recognizer.PartialResult(), false);
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
				
				if (_isRecording && !_moveAcceptedThisBeat && !string.IsNullOrEmpty(spokenText))
				{
					var matches = RecognizedTermPattern.Matches(spokenText);
					if (matches.Count > 0)
					{
						string matchedTerm = Regex.Replace(matches[0].Value, @"\s+", " ").ToLowerInvariant();
						_moveAcceptedThisBeat = true;
						_outputLabel.Text = $"Beat {_beatNumber}: {matchedTerm}";
					}
				}
			}
		}
		catch (Exception)
		{
			// Ignore parse errors on partials
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
