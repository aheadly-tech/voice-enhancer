//
//  VoiceEnhancer-Bridging-Header.h
//
//  Wired up via the SWIFT_OBJC_BRIDGING_HEADER build setting in
//  project.yml. Its only job is to expose the C ABI to Swift so the
//  `canImport(VoiceEnhancerEngine)` branch in AudioEngineBridge.swift
//  can call the real engine instead of the stub.
//

#ifndef VoiceEnhancer_Bridging_Header_h
#define VoiceEnhancer_Bridging_Header_h

#include "engine_c_api.h"

#endif /* VoiceEnhancer_Bridging_Header_h */
