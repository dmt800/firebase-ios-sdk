// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import FirebaseCore
import GoogleDataTransport

/// Extension to set Firebase app info.
extension SystemInfo {
  mutating func setAppInfo(apiKey: String?, projectID: String?) {
    appID = Bundle.main.bundleIdentifier ?? "unknownBundleID"
    // appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknownAppVersion"
    appVersion = "1"
    self.apiKey = apiKey ?? "unknownAPIKey"
    firebaseProjectID = projectID ?? "unknownProjectID"
  }
}

/// Extension to set model options.
extension ModelOptions {
  mutating func setModelOptions(model: CustomModel, isModelUpdateEnabled: Bool? = nil) {
    if let updateEnabled = isModelUpdateEnabled {
      self.isModelUpdateEnabled = updateEnabled
    }
    modelInfo.name = model.name
    modelInfo.hash = model.hash
    modelInfo.modelType = .custom
  }
}

/// Extension to build model download log event.
extension ModelDownloadLogEvent {
  mutating func setEvent(status: DownloadStatus, errorCode: ErrorCode? = nil,
                         roughDownloadDuration: UInt64? = nil, exactDownloadDuration: UInt64? = nil,
                         downloadFailureStatus: Int64? = nil, modelOptions: ModelOptions) {
    downloadStatus = status
    if let code = errorCode {
      self.errorCode = code
    }
    if let roughDuration = roughDownloadDuration {
      roughDownloadDurationMs = roughDuration
    }
    if let exactDuration = exactDownloadDuration {
      exactDownloadDurationMs = exactDuration
    }
    if let failureStatus = downloadFailureStatus {
      self.downloadFailureStatus = failureStatus
    }
    options = modelOptions
  }
}

/// Extension to build Firebase ML log event.
extension FirebaseMlLogEvent {
  mutating func setEvent(eventName: EventName, systemInfo: SystemInfo,
                         modelDownloadLogEvent: ModelDownloadLogEvent) {
    self.eventName = eventName
    self.systemInfo = systemInfo
    self.modelDownloadLogEvent = modelDownloadLogEvent
  }
}

/// Data object for Firelog event.
class FBMLDataObject: NSObject, GDTCOREventDataObject {
  private let event: FirebaseMlLogEvent

  init(event: FirebaseMlLogEvent) {
    self.event = event
  }

  /// Encode Firelog event for transport.
  func transportBytes() -> Data {
    do {
      // TODO: Should this be binary or json serialized?
      let data = try event.serializedData()
      print(try event.jsonString())
      return data
    } catch {
      DeviceLogger.logEvent(
        level: .debug,
        category: .analytics,
        message: "Unable to encode Firelog event.",
        messageCode: .analyticsEventEncodeError
      )
      return Data()
    }
  }
}

/// Firelog logger.
class TelemetryLogger {
  private let mappingID = "1326"
  let isStatsEnabled: Bool
  let fllTransport: GDTCORTransport

  private let apiKey: String?
  private let projectID: String?

  /// Init logger, could be nil if unable to get event transport.
  init?(isStatsEnabled: Bool, apiKey: String?, projectID: String?) {
    self.isStatsEnabled = isStatsEnabled
    self.apiKey = apiKey
    self.projectID = projectID
    guard let fllTransport = GDTCORTransport(
      mappingID: mappingID,
      transformers: nil,
      target: GDTCORTarget.FLL
    ) else {
      DeviceLogger.logEvent(
        level: .debug,
        category: .analytics,
        message: "Unable to create telemetry logger.",
        messageCode: .telemetryInitError
      )
      return nil
    }
    self.fllTransport = fllTransport
  }

  /// Log events to Firelog.
  private func logModelEvent(event: FirebaseMlLogEvent) {
    let eventForTransport: GDTCOREvent = fllTransport.eventForTransport()
    eventForTransport.dataObject = FBMLDataObject(event: event)
    eventForTransport.qosTier = .qoSFast
    fllTransport.sendDataEvent(eventForTransport)
  }

  /// Log model download event to Firelog.
  func logModelDownloadEvent(eventName: EventName, status: ModelDownloadStatus,
                             model: CustomModel? = nil) {
    var modelOptions = ModelOptions()
    if let model = model {
      modelOptions.setModelOptions(model: model)
    }
    var systemInfo = SystemInfo()
    systemInfo.setAppInfo(apiKey: apiKey, projectID: projectID)

    var modelDownloadLogEvent = ModelDownloadLogEvent()
    switch status {
    case .successful: modelDownloadLogEvent.setEvent(status: .succeeded, modelOptions: modelOptions)
    case .failed: modelDownloadLogEvent.setEvent(status: .failed, modelOptions: modelOptions)
    case .notStarted, .inProgress: break
    }
    var fbmlEvent = FirebaseMlLogEvent()
    fbmlEvent.setEvent(
      eventName: eventName,
      systemInfo: systemInfo,
      modelDownloadLogEvent: modelDownloadLogEvent
    )
    logModelEvent(event: fbmlEvent)
  }
}
