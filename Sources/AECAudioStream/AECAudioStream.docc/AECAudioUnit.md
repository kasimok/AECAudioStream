# ``AECAudioStream``

Automatic Echo Cancellation done via VoiceProcessingIO audio unit

## Overview

The ``AECAudioStream`` class provides an interface for capturing audio data from the system's audio input and applying an acoustic echo cancellation (AEC) filter to it. The class also allows you to play audio data through the audio unit's speaker using a renderer callback. 

> Acoustic Echo Cancellation (AEC) is a common signal processing technique used to remove the echo that occurs when a sound is played through a speaker and picked up by a microphone. This type of echo is called acoustic echo and can be very distracting and annoying for people on the other end of a phone or video call.
> AEC works by analyzing the audio signal that is being played through the speaker and subtracting it from the audio signal that is being picked up by the microphone. This process is done in real-time and requires a lot of computational power.
> AEC is commonly used in teleconferencing systems, video conferencing systems(VOIP), and other communication systems where audio is transmitted over a network. It helps to improve the quality of the audio signal and make communication more effective.


