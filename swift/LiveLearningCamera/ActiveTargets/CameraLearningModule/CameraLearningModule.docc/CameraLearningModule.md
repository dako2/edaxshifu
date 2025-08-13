# ``CameraLearningModule``

## Overview

CameraLearningModule is a modular framework extracted from the LiveLearningCamera application. This module encapsulates the core machine learning and computer vision capabilities, providing a reusable and testable foundation for camera-based learning systems.

## Purpose

This module was refactored from the main LiveLearningCamera app to:
- **Separate concerns** - Isolate ML/CV logic from UI and app-specific code
- **Enable reusability** - Allow the learning capabilities to be used in other projects
- **Improve testability** - Create a focused module that can be independently tested
- **Simplify maintenance** - Keep complex ML pipelines in a dedicated, versioned framework

## Core Components

### Object Detection Pipeline
- **YOLO Integration** - Real-time object detection using YOLOv11
- **Hand Tracking** - Specialized hand landmark detection and tracking
- **MobileViT** - Vision transformer for enhanced classification

### Learning & Memory Systems
- **Object Memory Manager** - Persistent storage of recognized objects
- **Scene Context Manager** - Environmental understanding and context tracking
- **Attention System** - Focus on relevant objects based on context
- **Learning Memory** - Adaptive learning from detection patterns

### Detection Services
- **Detection Stabilizer** - Smooths detection results across frames
- **Object Tracker** - Maintains object identity across video frames
- **Deduplication Manager** - Prevents duplicate detections
- **Visual Feature Extractor** - Extracts meaningful features for classification

## Architecture

```
CameraLearningModule/
├── Detection Layer
│   ├── YOLO Detector
│   ├── Hand Tracker
│   └── MobileViT Classifier
├── Processing Layer
│   ├── Stabilization
│   ├── Tracking
│   └── Deduplication
├── Learning Layer
│   ├── Memory Management
│   ├── Context Analysis
│   └── Attention System
└── Core Data Layer
    ├── Object Persistence
    └── Session Management
```

## Integration

The module integrates with the main LiveLearningCamera app through:
- **MLPipeline** - Coordinates the detection and learning pipeline
- **CameraManager** - Handles camera feed and frame processing
- **CoreDataManager** - Manages persistent storage

## Key Features

1. **Real-time Processing** - Optimized for live camera feed analysis
2. **Adaptive Learning** - Improves detection accuracy over time
3. **Context Awareness** - Understands scene relationships
4. **Memory Persistence** - Remembers objects across sessions
5. **Modular Design** - Easy to extend with new detection models

## Usage

```swift
import CameraLearningModule

// Initialize the learning module
let learningModule = CameraLearningModule()

// Configure detection settings
learningModule.configure(
    enableYOLO: true,
    enableHandTracking: true,
    enableLearning: true
)

// Process camera frames
learningModule.processFrame(cameraBuffer) { detections in
    // Handle detection results
}
```

## Dependencies

- Core ML for model inference
- Vision framework for image processing
- Core Data for persistence
- AVFoundation for camera integration

## Future Enhancements

- Additional detection models
- Enhanced learning algorithms
- Cloud synchronization for learned data
- Performance optimizations for older devices

## License

Part of the LiveLearningCamera project - see main project license for details.
