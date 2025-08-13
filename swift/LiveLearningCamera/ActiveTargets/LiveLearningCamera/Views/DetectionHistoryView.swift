//
//  DetectionHistoryView.swift
//  LiveLearningCamera
//
//  View for displaying captured detection history
//

import SwiftUI
import CoreData
import CameraLearningModule

struct DetectionHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CapturedDetection.captureDate, ascending: false)],
        animation: .default
    )
    private var detections: FetchedResults<CapturedDetection>
    
    @State private var selectedClass: String? = nil
    @State private var showingStatistics = false
    
    private let coreDataManager = CoreDataManager.shared
    
    var body: some View {
        NavigationView {
            VStack {
                // Statistics Header
                if showingStatistics {
                    StatisticsHeaderView()
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
                
                // Filter Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        FilterChip(title: "All", isSelected: selectedClass == nil) {
                            selectedClass = nil
                        }
                        
                        ForEach(uniqueClasses, id: \.self) { className in
                            FilterChip(title: className, isSelected: selectedClass == className) {
                                selectedClass = className
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                // Detection List
                List {
                    ForEach(filteredDetections) { detection in
                        DetectionRowView(detection: detection)
                    }
                    .onDelete(perform: deleteDetections)
                }
            }
            .navigationTitle("Detection History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingStatistics.toggle() }) {
                        Image(systemName: "chart.bar.fill")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }
    
    private var filteredDetections: [CapturedDetection] {
        if let selectedClass = selectedClass {
            return detections.filter { $0.label == selectedClass }
        }
        return Array(detections)
    }
    
    private var uniqueClasses: [String] {
        let classes = Set(detections.compactMap { $0.label })
        return Array(classes).sorted()
    }
    
    private func deleteDetections(offsets: IndexSet) {
        withAnimation {
            offsets.map { filteredDetections[$0] }.forEach(viewContext.delete)
            coreDataManager.saveContext()
        }
    }
}

// MARK: - Detection Row View
struct DetectionRowView: View {
    let detection: CapturedDetection
    
    var body: some View {
        HStack {
            // Thumbnail
            if let image = detection.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(detection.label ?? "Unknown")
                    .font(.headline)
                
                HStack {
                    Label(String(format: "%.1f%%", detection.confidence * 100), systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    if let supercategory = detection.supercategory {
                        Text("• \(supercategory)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let date = detection.captureDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(15)
        }
    }
}

// MARK: - Statistics Header
struct StatisticsHeaderView: View {
    private let coreDataManager = CoreDataManager.shared
    @State private var statistics = DetectionStatistics(
        totalDetections: 0,
        classCounts: [:],
        averageConfidence: 0,
        mostCommonClass: nil
    )
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.headline)
            
            HStack {
                StatItem(
                    icon: "number",
                    title: "Total",
                    value: "\(statistics.totalDetections)"
                )
                
                Spacer()
                
                StatItem(
                    icon: "percent",
                    title: "Avg Confidence",
                    value: String(format: "%.1f%%", statistics.averageConfidence * 100)
                )
                
                Spacer()
                
                if let mostCommon = statistics.mostCommonClass {
                    StatItem(
                        icon: "star.fill",
                        title: "Most Common",
                        value: mostCommon
                    )
                }
            }
        }
        .onAppear {
            statistics = coreDataManager.getDetectionStatistics()
        }
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Preview
struct DetectionHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        DetectionHistoryView()
            .environment(\.managedObjectContext, CoreDataManager.shared.context)
    }
}