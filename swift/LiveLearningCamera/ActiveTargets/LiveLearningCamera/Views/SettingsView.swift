//
//  SettingsView.swift
//  LiveLearningCamera
//
//  Settings UI for configuring detection options
//

import SwiftUI
import CameraLearningModule

struct SettingsView: View {
    @ObservedObject var settings = DetectionSettingsManager.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Detection Mode")) {
                    Toggle("Enable Classification", isOn: $settings.showClassification)
                        .accessibilityIdentifier("enableClassificationToggle")
                    
                    if settings.showClassification {
                        Toggle(isOn: $settings.useCOCOLabels) {
                            VStack(alignment: .leading) {
                                Text("Use COCO Class Names")
                                Text(settings.useCOCOLabels ? 
                                     "Shows: person, dog, car, etc." : 
                                     "Shows: class_0, class_16, class_2, etc.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .accessibilityIdentifier("useCOCOLabelsToggle")
                    } else {
                        Text("All detections shown as 'object'")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Class Filter")) {
                    Toggle("Enable Class Filter", isOn: $settings.useClassFilter)
                        .accessibilityIdentifier("enableClassFilterToggle")
                    
                    if settings.useClassFilter {
                        ForEach(settings.sortedCategoryNames, id: \.self) { category in
                            Toggle(category, isOn: Binding(
                                get: { settings.isCategoryEnabled(category) },
                                set: { _ in settings.toggleCategory(category) }
                            ))
                            .accessibilityIdentifier("category_\(category)")
                        }
                        
                        Text("\(settings.enabledClasses.count) of 80 classes enabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Display Options")) {
                    Toggle("Show Confidence Score", isOn: $settings.showConfidence)
                        .accessibilityIdentifier("showConfidenceToggle")
                    Toggle("Show FPS Counter", isOn: $settings.showFPS)
                        .accessibilityIdentifier("showFPSToggle")
                }
                
                Section(header: Text("Capture Settings")) {
                    Toggle("Enable Deduplication", isOn: $settings.enableDeduplication)
                        .accessibilityIdentifier("enableDeduplicationToggle")
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Capture Interval")
                            Spacer()
                            Text(String(format: "%.1fs", settings.captureInterval))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.captureInterval, in: 0.5...5.0, step: 0.5)
                            .accessibilityIdentifier("captureIntervalSlider")
                        Text("Minimum time between captures to avoid duplicates")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Hand Tracking")) {
                    Toggle("Enable Hand Tracking", isOn: $settings.enableHandTracking)
                        .accessibilityIdentifier("enableHandTrackingToggle")
                    
                    if settings.enableHandTracking {
                        Toggle("Show Hand Gestures", isOn: $settings.showHandGestures)
                            .accessibilityIdentifier("showHandGesturesToggle")
                        Toggle("Show Hand Landmarks", isOn: $settings.showHandLandmarks)
                            .accessibilityIdentifier("showHandLandmarksToggle")
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Max Hands")
                                Spacer()
                                Text("\(settings.maxHandCount)")
                                    .foregroundColor(.secondary)
                            }
                            Picker("Max Hands", selection: $settings.maxHandCount) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .accessibilityIdentifier("maxHandsPicker")
                        }
                        
                        Text("Detects hands with 21 landmarks and gesture recognition")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Detection Threshold")) {
                    VStack {
                        HStack {
                            Text("Confidence")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.confidenceThreshold * 100))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.confidenceThreshold, in: 0.1...0.9, step: 0.05)
                            .accessibilityIdentifier("confidenceThresholdSlider")
                    }
                    Text("Lower values detect more objects but may include false positives")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Models")
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("YOLOv11n")
                            if settings.enableHandTracking {
                                Text("Vision Hand Pose")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Classes")
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("80 COCO Classes")
                            if settings.enableHandTracking {
                                Text("+ Hand Gestures")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(isPresented: .constant(true))
    }
}