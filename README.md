# ``AECAudioStream``

Automatic Echo Cancellation done via VoiceProcessingIO audio unit

## Overview

The ``AECAudioStream`` class provides an interface for capturing audio data from the system's audio input and applying an acoustic echo cancellation (AEC) filter to it. The class also allows you to play audio data through the audio unit's speaker using a renderer callback. 

### About AEC

Acoustic Echo Cancellation (AEC) is a common signal processing technique used to remove the echo that occurs when a sound is played through a speaker and picked up by a microphone. This type of echo is called acoustic echo and can be very distracting and annoying for people on the other end of a phone or video call.

AEC works by analyzing the audio signal that is being played through the speaker and subtracting it from the audio signal that is being picked up by the microphone. This process is done in real-time and requires a lot of computational power.

AEC is commonly used in teleconferencing systems, video conferencing systems(VOIP), and other communication systems where audio is transmitted over a network. It helps to improve the quality of the audio signal and make communication more effective.

![A diagram explaining Echo Cancellation](./Sources/AECAudioStream/AECAudioStream.docc/Resources/documentaion-art/AEC\~light@2x.png)

### Create a AECAudioStream

To create a standard AudioStream without any special renderrer callback, you initialize a new instance of the ``AECAudioStream`` class, and supply a sampling rate for the recorded Audio, as the following code shows:

```swift
  /// Audio Samping at 16000Hz
  let audioUnit = AECAudioStream(sampleRate: 16000)
```


### Get AEC Filtered Audio Data from AECAudioStream

After an AudioStream object is created, you can listen for recorded audio data by calling ``AECAudioStream/AECAudioStream/startAudioStream(enableAEC:)`` it returns an `AsyncThrowingStream` that yields `AVAudioPCMBuffer` objects containing the captured audio data.

```swift
for try await pcmBuffer in audioUnit.startAudioStream(enableAEC: true) {
  // here you get a ``AVAudioPCMBuffer`` data
  pushStream?.write(pcmBuffer.data())
}
```

Alternatively, if you are not familiar with `AsyncThrowingStream` manner, you can call ``AECAudioStream/AECAudioStream/startAudioStream(enableAEC:audioBufferHandler:)``, the audio data will be provided in the `audioBufferHandler`

```swift
audioUnit.startAudioStream(enableAEC: true, audioBufferHandler: { pcmBuffer in
  // here you get a ``AVAudioPCMBuffer`` data
})
```

### Stop the AECAudioStream

Stop a running AudioStream object is simple, just call ``AECAudioStream/AECAudioStream/stopAudioUnit()``. It will stops the audio unit and disposes of the audio graph.

## Topics

### Essentials

- ``AudioToolbox/kAudioUnitSubType_VoiceProcessingIO``
