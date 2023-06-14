//
//  ECAudioUnit.swift
//  AECAudioUnit
//
//  Created by 0x67 on 2023-06-13.
//

import Foundation
import AVFAudio
import OSLog

/**
 The `AECAudioStream` class provides an interface for capturing audio data from the system's audio input and applying an acoustic echo cancellation (AEC) filter to it. The class also allows you to play audio data through the audio unit's speaker using a renderer callback(testing feature).
 
 To use this class, create an instance with the desired sample rate and enable the renderer callback if needed. Then call the `startAudioStream` method to start capturing audio data and applying the AEC filter.
 
 - Version: 1.0
 */
public class AECAudioStream {
  
  private(set) var audioUnit: AudioUnit!
  
  private(set) var graph: AUGraph!
  
  private(set) var streamBasicDescription: AudioStreamBasicDescription
  
  private let logger = Logger(subsystem: "com.0x67.echo-cancellation.AECAudioUnit", category: "AECAudioStream")
  
  private(set) var sampleRate: Float64
  
  private(set) var streamFormat: AVAudioFormat
  
  private(set) var enableAutomaticEchoCancellation: Bool = false
  
  /// Provide AudioBufferList data in this closure to have speaker in this audio unit play you audio, only works if ``enableRendererCallback`` is set to `true`
  public var rendererClosure: ((UnsafeMutablePointer<AudioBufferList>, UInt32) -> Void)?
  
  /// A Boolean value that indicates whether to enable built-in audio unit's renderrer callback
  public var enableRendererCallback: Bool = false
  
  private(set) var capturedFrameHandler: ((AVAudioPCMBuffer) -> Void)?
  
  /**
   Initializes an instance of an audio stream object with the specified sample rate.
   
   - Parameter sampleRate: The sample rate of the audio stream.
   
   - Parameter enableRendererCallback: A Boolean value that indicates whether to enable a renderer callback, if enabled data provided in `rendererClosure` will be send to speaker
   
   - Parameter rendererClosure: A closure that takes an `UnsafeMutablePointer<AudioBufferList>` and a `UInt32` as input.
   
   - Returns: None.
   */
  public init(sampleRate: Float64,
              enableRendererCallback: Bool = false,
              rendererClosure: ((UnsafeMutablePointer<AudioBufferList>, UInt32) -> Void)? = nil) {
    self.sampleRate = sampleRate
    self.streamBasicDescription = Self.canonicalStreamDescription(sampleRate: sampleRate)
    self.streamFormat = AVAudioFormat(streamDescription: &self.streamBasicDescription)!
    self.enableRendererCallback = enableRendererCallback
    self.rendererClosure = rendererClosure
  }
  
  /**
   Starts an audio stream filter that captures audio data from the system's audio input and applies an acoustic echo cancellation (AEC) filter to it.
   
   - Parameter enableAEC: A Boolean value that indicates whether to enable the AEC filter.
   
   - Returns: An `AsyncThrowingStream` that yields `AVAudioPCMBuffer` objects containing the captured audio data.
   
   - Throws: An error if there was a problem creating or configuring the audio unit, or if the AEC filter could not be enabled.
   */
  public func startAudioStream(enableAEC: Bool) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
    AsyncThrowingStream<AVAudioPCMBuffer, Error> { continuation in
      do {
        try createAUGraphForAudioUnit()
        try configureAudioUnit()
        try toggleAudioCancellation(enable: enableAEC)
        try startGraph()
        try startAudioUnit()
        self.capturedFrameHandler = {continuation.yield($0)}
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }
  
  /**
   Starts an audio stream  that captures audio data from the system's audio input and applies an acoustic echo cancellation (AEC) filter to it.
   
   - Parameter enableAEC: A Boolean value that indicates whether to enable the AEC filter.
   
   - Parameter audioBufferHandler: A closure that takes an `AVAudioPCMBuffer` object containing the captured audio data.
   
   - Returns: None.
   
   - Throws: An error if there was a problem creating or configuring the audio unit, or if the AEC filter could not be enabled.
   */
  public func startAudioStream(enableAEC: Bool, audioBufferHandler: @escaping (AVAudioPCMBuffer) -> Void ) throws {
    try createAUGraphForAudioUnit()
    try configureAudioUnit()
    try toggleAudioCancellation(enable: enableAEC)
    try startGraph()
    try startAudioUnit()
    self.capturedFrameHandler = audioBufferHandler
  }
  
  /**
   Stops the audio unit and disposes of the audio graph.
   
   - Throws: An `AECAudioStreamError` if any of the operations fail.
   
   - Returns: None.
   */
  public func stopAudioUnit() throws {
    var status = AUGraphStop(graph!)
    guard status == noErr else {
      logger.error("AUGraphStop failed")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    status = AudioUnitUninitialize(audioUnit!)
    guard status == noErr else {
      logger.error("AudioUnitUninitialize failed")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    status = DisposeAUGraph(graph!)
    guard status == noErr else {
      logger.error("DisposeAUGraph failed")
      throw AECAudioStreamError.osStatusError(status: status)
    }
  }
  
  private func toggleAudioCancellation(enable: Bool) throws {
    self.enableAutomaticEchoCancellation = enable
    // 0 means feature is enabled, which includes built-in echo cancellation. When the property is set to true, the voice processing feature is bypassed and no echo cancellation is performed.
    var bypassVoiceProcessing: UInt32 = self.enableAutomaticEchoCancellation ? 0 : 1
    let status = AudioUnitSetProperty(audioUnit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &bypassVoiceProcessing, UInt32(MemoryLayout.size(ofValue: bypassVoiceProcessing)))
    guard status == noErr else {
      logger.error("Error in [AudioUnitSetProperty|kAUVoiceIOProperty_BypassVoiceProcessing|kAudioUnitScope_Global]")
      throw AECAudioStreamError.osStatusError(status: status)
    }
  }
  
  private func startGraph() throws {
    var status = AUGraphInitialize(graph!)
    guard status == noErr else {
      throw AECAudioStreamError.osStatusError(status: status)
    }
    status = AUGraphStart(graph!)
    guard status == noErr else {
      throw AECAudioStreamError.osStatusError(status: status)
    }
  }
  
  private func startAudioUnit() throws {
    let status = AudioOutputUnitStart(audioUnit!)
    guard AudioOutputUnitStart(audioUnit) == noErr else {
      throw AECAudioStreamError.osStatusError(status: status)
    }
  }
  
  private func createAUGraphForAudioUnit() throws {
    // Create AUGraph
    var status = NewAUGraph(&graph)
    guard status == noErr else {
      logger.error("Error in [NewAUGraph]")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    
    // Create nodes and add to the graph
    var inputcd = AudioComponentDescription()
    inputcd.componentType = kAudioUnitType_Output
    inputcd.componentSubType = kAudioUnitSubType_VoiceProcessingIO
    inputcd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    // Add the input node to the graph
    var remoteIONode: AUNode = 0
    status = AUGraphAddNode(graph!, &inputcd, &remoteIONode)
    guard status == noErr else {
      logger.error("AUGraphAddNode failed")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    
    // Open the graph
    status = AUGraphOpen(graph!)
    guard status == noErr else {
      logger.error("AUGraphOpen failed")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    
    // Get a reference to the input node
    status = AUGraphNodeInfo(graph!, remoteIONode, &inputcd, &audioUnit)
    guard status == noErr else {
      logger.error("AUGraphNodeInfo failed")
      throw AECAudioStreamError.osStatusError(status: status)
    }
  }
  
  /// Create a canonical StreamDescription for kAudioUnitSubType_VoiceProcessingIO
  /// - Parameter sampleRate: sample rate
  /// - Returns: canonical AudioStreamBasicDescription
  static func canonicalStreamDescription(sampleRate: Float64) -> AudioStreamBasicDescription {
    var canonicalBasicStreamDescription = AudioStreamBasicDescription()
    canonicalBasicStreamDescription.mSampleRate = sampleRate
    canonicalBasicStreamDescription.mFormatID = kAudioFormatLinearPCM
    canonicalBasicStreamDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    canonicalBasicStreamDescription.mFramesPerPacket = 1
    canonicalBasicStreamDescription.mChannelsPerFrame = 1 //Mono Channel
    canonicalBasicStreamDescription.mBitsPerChannel = 16
    canonicalBasicStreamDescription.mBytesPerPacket = 2
    canonicalBasicStreamDescription.mBytesPerFrame = 2
    return canonicalBasicStreamDescription
  }
  
  
  private func configureAudioUnit() throws {
    // Bus 0 provides output to hardware and bus 1 accepts input from hardware. See the Voice-Processing I/O Audio Unit Properties(`kAudioUnitSubType_VoiceProcessingIO`) for the identifiers for this audio unit’s properties. 
    let bus_0_output: AudioUnitElement = 0
    let bus_1_input: AudioUnitElement = 1
    
    var enableInput: UInt32 = 1
    var status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, bus_1_input, &enableInput, UInt32(MemoryLayout.size(ofValue: enableInput)))
    guard status == noErr else {
      AudioComponentInstanceDispose(audioUnit)
      logger.error("Error in [AudioUnitSetProperty|kAudioUnitScope_Input]")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    
    var enableOutput: UInt32 = enableRendererCallback ? 1 : 0
    status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, bus_0_output, &enableOutput, UInt32(MemoryLayout.size(ofValue: enableOutput)))
    guard status == noErr else {
      AudioComponentInstanceDispose(audioUnit)
      logger.error("Error in [AudioUnitSetProperty|kAudioUnitScope_Output]")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    
    status = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus_1_input, &self.streamBasicDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    guard status == noErr else {
      AudioComponentInstanceDispose(audioUnit)
      logger.error("Error in [AudioUnitSetProperty|kAudioUnitProperty_StreamFormat|kAudioUnitScope_Output]")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    
    
    status = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, bus_0_output, &self.streamBasicDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    guard status == noErr else {
      AudioComponentInstanceDispose(audioUnit)
      logger.error("Error in [AudioUnitSetProperty|kAudioUnitProperty_StreamFormat|kAudioUnitScope_Input]")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    
    // Set the input callback for the audio unit
    var inputCallbackStruct = AURenderCallbackStruct()
    inputCallbackStruct.inputProc = kInputCallback
    inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
    status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Input, bus_1_input, &inputCallbackStruct, UInt32(MemoryLayout.size(ofValue: inputCallbackStruct)))
    guard status == noErr else {
      logger.error("Error in [AudioUnitSetProperty|kAudioOutputUnitProperty_SetInputCallback|kAudioUnitScope_Input]")
      throw AECAudioStreamError.osStatusError(status: status)
    }
    
    if enableRendererCallback {
      // Set the input callback for the audio unit
      var outputCallbackStruct = AURenderCallbackStruct()
      outputCallbackStruct.inputProc = kRenderCallback
      outputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
      status = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Output, bus_0_output, &outputCallbackStruct, UInt32(MemoryLayout.size(ofValue: outputCallbackStruct)))
      guard status == noErr else {
        logger.error("Error in [AudioUnitSetProperty|kAudioOutputUnitProperty_SetInputCallback|kAudioUnitScope_Output]")
        throw AECAudioStreamError.osStatusError(status: status)
      }
    }
  }
}

private func kInputCallback(inRefCon:UnsafeMutableRawPointer,
                            ioActionFlags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                            inTimeStamp:UnsafePointer<AudioTimeStamp>,
                            inBusNumber:UInt32,
                            inNumberFrames:UInt32,
                            ioData:UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
  
  let audioMgr = unsafeBitCast(inRefCon, to: AECAudioStream.self)
  
  let audioBuffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
  
  var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
  
  let status = AudioUnitRender(audioMgr.audioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &bufferList)
  
  guard status == noErr else { return status }
  
  if let buffer = AVAudioPCMBuffer(pcmFormat: audioMgr.streamFormat, bufferListNoCopy: &bufferList), let captureAudioFrameHandler = audioMgr.capturedFrameHandler {
    captureAudioFrameHandler(buffer)
  }
  return noErr
}

private func kRenderCallback(inRefCon:UnsafeMutableRawPointer,
                             ioActionFlags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                             inTimeStamp:UnsafePointer<AudioTimeStamp>,
                             inBusNumber:UInt32,
                             inNumberFrames:UInt32,
                             ioData:UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
  
  let audioMgr = unsafeBitCast(inRefCon, to: AECAudioStream.self)
  
  if let rendererClosure = audioMgr.rendererClosure {
    rendererClosure(ioData!, inNumberFrames)
  } else {
    fatalError("Renderer callback enabled but not renderrerClosure is assigned.")
  }
  
  return noErr
}
