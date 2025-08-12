//
//  COCOClasses.swift
//  LiveLearningCamera
//
//  COCO dataset class definitions and metadata
//

import Foundation

struct COCOClass: Codable, Identifiable {
    let id: Int
    let name: String
    let supercategory: String
}

class COCODataset {
    static let shared = COCODataset()
    
    // Official COCO 80 classes with supercategories from COCO dataset
    let classes: [COCOClass] = [
        // Person
        COCOClass(id: 0, name: "person", supercategory: "person"),
        
        // Vehicle
        COCOClass(id: 1, name: "bicycle", supercategory: "vehicle"),
        COCOClass(id: 2, name: "car", supercategory: "vehicle"),
        COCOClass(id: 3, name: "motorcycle", supercategory: "vehicle"),
        COCOClass(id: 4, name: "airplane", supercategory: "vehicle"),
        COCOClass(id: 5, name: "bus", supercategory: "vehicle"),
        COCOClass(id: 6, name: "train", supercategory: "vehicle"),
        COCOClass(id: 7, name: "truck", supercategory: "vehicle"),
        COCOClass(id: 8, name: "boat", supercategory: "vehicle"),
        
        // Outdoor
        COCOClass(id: 9, name: "traffic light", supercategory: "outdoor"),
        COCOClass(id: 10, name: "fire hydrant", supercategory: "outdoor"),
        COCOClass(id: 11, name: "stop sign", supercategory: "outdoor"),
        COCOClass(id: 12, name: "parking meter", supercategory: "outdoor"),
        COCOClass(id: 13, name: "bench", supercategory: "outdoor"),
        
        // Animal
        COCOClass(id: 14, name: "bird", supercategory: "animal"),
        COCOClass(id: 15, name: "cat", supercategory: "animal"),
        COCOClass(id: 16, name: "dog", supercategory: "animal"),
        COCOClass(id: 17, name: "horse", supercategory: "animal"),
        COCOClass(id: 18, name: "sheep", supercategory: "animal"),
        COCOClass(id: 19, name: "cow", supercategory: "animal"),
        COCOClass(id: 20, name: "elephant", supercategory: "animal"),
        COCOClass(id: 21, name: "bear", supercategory: "animal"),
        COCOClass(id: 22, name: "zebra", supercategory: "animal"),
        COCOClass(id: 23, name: "giraffe", supercategory: "animal"),
        
        // Accessory
        COCOClass(id: 24, name: "backpack", supercategory: "accessory"),
        COCOClass(id: 25, name: "umbrella", supercategory: "accessory"),
        COCOClass(id: 26, name: "handbag", supercategory: "accessory"),
        COCOClass(id: 27, name: "tie", supercategory: "accessory"),
        COCOClass(id: 28, name: "suitcase", supercategory: "accessory"),
        
        // Sports
        COCOClass(id: 29, name: "frisbee", supercategory: "sports"),
        COCOClass(id: 30, name: "skis", supercategory: "sports"),
        COCOClass(id: 31, name: "snowboard", supercategory: "sports"),
        COCOClass(id: 32, name: "sports ball", supercategory: "sports"),
        COCOClass(id: 33, name: "kite", supercategory: "sports"),
        COCOClass(id: 34, name: "baseball bat", supercategory: "sports"),
        COCOClass(id: 35, name: "baseball glove", supercategory: "sports"),
        COCOClass(id: 36, name: "skateboard", supercategory: "sports"),
        COCOClass(id: 37, name: "surfboard", supercategory: "sports"),
        COCOClass(id: 38, name: "tennis racket", supercategory: "sports"),
        
        // Kitchen
        COCOClass(id: 39, name: "bottle", supercategory: "kitchen"),
        COCOClass(id: 40, name: "wine glass", supercategory: "kitchen"),
        COCOClass(id: 41, name: "cup", supercategory: "kitchen"),
        COCOClass(id: 42, name: "fork", supercategory: "kitchen"),
        COCOClass(id: 43, name: "knife", supercategory: "kitchen"),
        COCOClass(id: 44, name: "spoon", supercategory: "kitchen"),
        COCOClass(id: 45, name: "bowl", supercategory: "kitchen"),
        
        // Food
        COCOClass(id: 46, name: "banana", supercategory: "food"),
        COCOClass(id: 47, name: "apple", supercategory: "food"),
        COCOClass(id: 48, name: "sandwich", supercategory: "food"),
        COCOClass(id: 49, name: "orange", supercategory: "food"),
        COCOClass(id: 50, name: "broccoli", supercategory: "food"),
        COCOClass(id: 51, name: "carrot", supercategory: "food"),
        COCOClass(id: 52, name: "hot dog", supercategory: "food"),
        COCOClass(id: 53, name: "pizza", supercategory: "food"),
        COCOClass(id: 54, name: "donut", supercategory: "food"),
        COCOClass(id: 55, name: "cake", supercategory: "food"),
        
        // Furniture
        COCOClass(id: 56, name: "chair", supercategory: "furniture"),
        COCOClass(id: 57, name: "couch", supercategory: "furniture"),
        COCOClass(id: 58, name: "potted plant", supercategory: "furniture"),
        COCOClass(id: 59, name: "bed", supercategory: "furniture"),
        COCOClass(id: 60, name: "dining table", supercategory: "furniture"),
        COCOClass(id: 61, name: "toilet", supercategory: "furniture"),
        
        // Electronic
        COCOClass(id: 62, name: "tv", supercategory: "electronic"),
        COCOClass(id: 63, name: "laptop", supercategory: "electronic"),
        COCOClass(id: 64, name: "mouse", supercategory: "electronic"),
        COCOClass(id: 65, name: "remote", supercategory: "electronic"),
        COCOClass(id: 66, name: "keyboard", supercategory: "electronic"),
        COCOClass(id: 67, name: "cell phone", supercategory: "electronic"),
        
        // Appliance
        COCOClass(id: 68, name: "microwave", supercategory: "appliance"),
        COCOClass(id: 69, name: "oven", supercategory: "appliance"),
        COCOClass(id: 70, name: "toaster", supercategory: "appliance"),
        COCOClass(id: 71, name: "sink", supercategory: "appliance"),
        COCOClass(id: 72, name: "refrigerator", supercategory: "appliance"),
        
        // Indoor
        COCOClass(id: 73, name: "book", supercategory: "indoor"),
        COCOClass(id: 74, name: "clock", supercategory: "indoor"),
        COCOClass(id: 75, name: "vase", supercategory: "indoor"),
        COCOClass(id: 76, name: "scissors", supercategory: "indoor"),
        COCOClass(id: 77, name: "teddy bear", supercategory: "indoor"),
        COCOClass(id: 78, name: "hair drier", supercategory: "indoor"),
        COCOClass(id: 79, name: "toothbrush", supercategory: "indoor")
    ]
    
    // Computed properties for dynamic access
    var classNames: [String] {
        classes.map { $0.name }
    }
    
    var supercategories: Set<String> {
        Set(classes.map { $0.supercategory })
    }
    
    var classesBySupercategory: [String: [COCOClass]] {
        Dictionary(grouping: classes, by: { $0.supercategory })
    }
    
    var classesByID: [Int: COCOClass] {
        Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0) })
    }
    
    // Methods
    func getClass(byID id: Int) -> COCOClass? {
        classesByID[id]
    }
    
    func getClassName(byID id: Int) -> String {
        classesByID[id]?.name ?? "unknown"
    }
    
    func getSupercategory(byID id: Int) -> String {
        classesByID[id]?.supercategory ?? "unknown"
    }
    
    func getClassIDs(forSupercategory supercategory: String) -> [Int] {
        classesBySupercategory[supercategory]?.map { $0.id } ?? []
    }
    
    // Search functionality
    func searchClasses(query: String) -> [COCOClass] {
        let lowercased = query.lowercased()
        return classes.filter { 
            $0.name.lowercased().contains(lowercased) ||
            $0.supercategory.lowercased().contains(lowercased)
        }
    }
    
    // Export for persistence
    func exportClassSelection(_ enabledIDs: Set<Int>) -> Data? {
        try? JSONEncoder().encode(Array(enabledIDs))
    }
    
    func importClassSelection(from data: Data) -> Set<Int>? {
        guard let array = try? JSONDecoder().decode([Int].self, from: data) else { return nil }
        return Set(array)
    }
}

// Extension for easy integration with existing code
extension COCODataset {
    static var legacyClassNames: [String] {
        shared.classNames
    }
}