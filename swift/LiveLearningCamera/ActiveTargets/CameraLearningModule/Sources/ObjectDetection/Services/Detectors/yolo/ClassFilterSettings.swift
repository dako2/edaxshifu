//
//  ClassFilterSettings.swift
//  LiveLearningCamera
//
//  Settings for filtering which COCO classes to detect
//

import SwiftUI

extension DetectionSettingsManager {
    // Use the proper COCO dataset structure
    private var cocoDataset: COCODataset {
        COCODataset.shared
    }
    
    // Dynamic categories from actual COCO supercategories
    var classCategories: [String: [Int]] {
        var categories: [String: [Int]] = [:]
        for supercategory in cocoDataset.supercategories {
            categories[supercategory.capitalized] = cocoDataset.getClassIDs(forSupercategory: supercategory)
        }
        return categories
    }
    
    // Get sorted category names
    public var sortedCategoryNames: [String] {
        classCategories.keys.sorted()
    }
    
    func loadClassFilter() {
        if let saved = UserDefaults.standard.array(forKey: "enabledClasses") as? [Int] {
            self.enabledClasses = Set(saved)
        }
        self.useClassFilter = UserDefaults.standard.bool(forKey: "useClassFilter")
    }
    
    func isClassEnabled(_ classIndex: Int) -> Bool {
        return !useClassFilter || enabledClasses.contains(classIndex)
    }
    
    public func toggleCategory(_ category: String) {
        guard let indices = classCategories[category] else { return }
        
        let categorySet = Set(indices)
        if categorySet.isSubset(of: enabledClasses) {
            // All enabled, so disable them
            enabledClasses.subtract(categorySet)
        } else {
            // Some disabled, so enable all
            enabledClasses.formUnion(categorySet)
        }
    }
    
    public func isCategoryEnabled(_ category: String) -> Bool {
        guard let indices = classCategories[category] else { return false }
        return Set(indices).isSubset(of: enabledClasses)
    }
}