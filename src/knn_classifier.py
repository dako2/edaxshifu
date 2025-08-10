"""
KNN Classifier for object recognition using ResNet18 embeddings.
"""

import torch
import torchvision.transforms as transforms
from torchvision.models import resnet18
from PIL import Image
import numpy as np
from sklearn.neighbors import KNeighborsClassifier
import cv2
import os
from typing import Optional, Dict, List, Tuple, Any
import logging
from dataclasses import dataclass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class Recognition:
    """Result of KNN recognition."""
    label: str
    confidence: float
    all_scores: Dict[str, float]
    embedding: np.ndarray
    is_known: bool  # True if confidence > threshold


class KNNObjectClassifier:
    """KNN classifier for few-shot object recognition."""
    
    def __init__(self, 
                 n_neighbors: int = 3,  # Changed to 3 for more robust predictions
                 confidence_threshold: float = 0.6,
                 model_path: Optional[str] = None,
                 device: Optional[str] = None,
                 max_samples_per_class: int = 100,
                 embedding_dim: int = 512):
        """
        Initialize KNN classifier with ResNet18 feature extractor.
        
        Args:
            n_neighbors: Number of neighbors for KNN
            confidence_threshold: Minimum confidence for "known" classification
            model_path: Path to save/load trained KNN model
            device: Device to run model on (cuda/cpu/auto)
            max_samples_per_class: Maximum samples to keep per class
            embedding_dim: Dimension of feature embeddings
        """
        self.n_neighbors = n_neighbors
        self.confidence_threshold = confidence_threshold
        self.model_path = model_path or "models/knn_classifier.npz"
        self.max_samples_per_class = max_samples_per_class
        self.embedding_dim = embedding_dim
        
        # Setup device
        if device == "auto" or device is None:
            self.device = "cuda" if torch.cuda.is_available() else "cpu"
        else:
            self.device = device
            
        logger.info(f"Using device: {self.device}")
        
        # Initialize ResNet18 feature extractor
        self._setup_feature_extractor()
        
        # Initialize KNN
        self.knn = KNeighborsClassifier(n_neighbors=n_neighbors, metric='cosine')
        initial_size = 100
        self.X_train = np.empty((0, self.embedding_dim), dtype=np.float32)
        self.y_train = np.array([], dtype=object)
        self._capacity = initial_size
        self._actual_size = 0
        self.trained = False
        
        # Thread safety
        import threading
        self._lock = threading.RLock()
        
        # Ensure model directory exists
        os.makedirs(os.path.dirname(self.model_path), exist_ok=True)
        
        # Try to load existing model
        self.load_model()
        
    def _setup_feature_extractor(self):
        """Setup ResNet18 for feature extraction."""
        # Load pretrained ResNet18
        self.feature_extractor = resnet18(weights='IMAGENET1K_V1')
        # Remove the final classification layer
        self.feature_extractor = torch.nn.Sequential(
            *list(self.feature_extractor.children())[:-1]
        )
        self.feature_extractor.eval()
        self.feature_extractor.to(self.device)
        
        # Image preprocessing
        self.transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],  # ImageNet stats
                std=[0.229, 0.224, 0.225]
            )
        ])
        
    def extract_embedding(self, image: np.ndarray) -> np.ndarray:
        """
        Extract feature embedding from image using ResNet18.
        
        Args:
            image: Image as numpy array (BGR from OpenCV)
            
        Returns:
            Normalized feature embedding vector
        """
        # Convert BGR to RGB
        if len(image.shape) == 3 and image.shape[2] == 3:
            image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        else:
            image_rgb = image
            
        # Convert to PIL Image
        image_pil = Image.fromarray(image_rgb)
        
        # Preprocess
        img_tensor = self.transform(image_pil).unsqueeze(0).to(self.device)
        
        # Extract features
        with torch.no_grad():
            embedding = self.feature_extractor(img_tensor).squeeze().cpu().numpy()
            
        # L2 normalize the embedding for cosine similarity
        norm = np.linalg.norm(embedding)
        if norm > 0:
            embedding = embedding / norm
            
        return embedding.astype(np.float32)
    
    def add_sample(self, image: np.ndarray, label: str, retrain: bool = True):
        """
        Add a training sample to the classifier with optimized memory management.
        
        Args:
            image: Image as numpy array
            label: Object label
            retrain: Whether to retrain the model immediately
        """
        with self._lock:
            embedding = self.extract_embedding(image)
            
            if self._actual_size >= len(self.X_train):
                new_size = max(self._capacity, self._actual_size * 2) if self._actual_size > 0 else self._capacity
                
                new_X = np.empty((new_size, self.embedding_dim), dtype=np.float32)
                if self._actual_size > 0:
                    new_X[:self._actual_size] = self.X_train[:self._actual_size]
                self.X_train = new_X
                
                new_y = np.empty(new_size, dtype=object)
                if self._actual_size > 0:
                    new_y[:self._actual_size] = self.y_train[:self._actual_size]
                self.y_train = new_y
                
                self._capacity = new_size
            
            # Add new sample efficiently
            self.X_train[self._actual_size] = embedding
            self.y_train[self._actual_size] = label
            self._actual_size += 1
            
            # Memory management: limit samples per class
            self._manage_memory()
            
            # Retrain KNN if requested and we have enough samples
            if retrain and self._actual_size >= self.n_neighbors:
                self._retrain_knn()
                
            logger.info(f"Added sample for '{label}'. Total samples: {self._actual_size}")
    
    def _manage_memory(self):
        """Manage memory by limiting samples per class."""
        if self._actual_size == 0:
            return
            
        active_y = self.y_train[:self._actual_size]
        unique_labels, counts = np.unique(active_y, return_counts=True)
        
        for label, count in zip(unique_labels, counts):
            if count > self.max_samples_per_class:
                # Keep only the most recent samples
                label_mask = active_y == label
                label_indices = np.where(label_mask)[0]
                
                # Keep the last max_samples_per_class samples
                keep_indices = label_indices[-self.max_samples_per_class:]
                remove_indices = label_indices[:-self.max_samples_per_class]
                
                # Create mask for samples to keep
                keep_mask = np.ones(self._actual_size, dtype=bool)
                keep_mask[remove_indices] = False
                
                active_X = self.X_train[:self._actual_size]
                X_filtered = active_X[keep_mask]
                y_filtered = active_y[keep_mask]
                
                self.X_train[:len(X_filtered)] = X_filtered
                self.y_train[:len(y_filtered)] = y_filtered
                self._actual_size = len(X_filtered)
                
                logger.debug(f"Pruned {len(remove_indices)} old samples for class '{label}'")
    
    def _retrain_knn(self):
        """Retrain the KNN model with current samples."""
        if self._actual_size == 0:
            return
            
        X_data = self.X_train[:self._actual_size]
        y_data = self.y_train[:self._actual_size]
        
        # Use min of n_neighbors and number of unique samples
        unique_labels = np.unique(y_data)
        actual_neighbors = min(self.n_neighbors, self._actual_size, len(unique_labels))
        
        self.knn = KNeighborsClassifier(
            n_neighbors=actual_neighbors,
            metric='cosine',  # Use cosine similarity for normalized embeddings
            algorithm='brute'  # More stable for high-dimensional data
        )
        self.knn.fit(X_data, y_data)
        self.trained = True
            
    def add_samples_from_directory(self, directory: str):
        """
        Add training samples from a directory structure.
        
        Supports two structures:
        1. Subdirectories for classes:
            directory/
                class1/
                    image1.jpg
        2. Flat structure with class in filename:
            directory/
                class1_image1.jpg
                class2_image1.jpg
        """
        if not os.path.exists(directory):
            logger.warning(f"Directory {directory} does not exist")
            return
            
        # First try to load from subdirectories
        found_subdirs = False
        for item in os.listdir(directory):
            item_path = os.path.join(directory, item)
            if os.path.isdir(item_path):
                found_subdirs = True
                class_name = item
                for img_file in os.listdir(item_path):
                    if img_file.lower().endswith(('.png', '.jpg', '.jpeg')):
                        img_path = os.path.join(item_path, img_file)
                        try:
                            img = cv2.imread(img_path)
                            if img is not None:
                                self.add_sample(img, class_name)
                                logger.info(f"Loaded {img_path} as class '{class_name}'")
                        except Exception as e:
                            logger.error(f"Error loading {img_path}: {e}")
                            
        # If no subdirectories, try flat structure
        if not found_subdirs:
            for img_file in os.listdir(directory):
                if img_file.lower().endswith(('.png', '.jpg', '.jpeg')):
                    img_path = os.path.join(directory, img_file)
                    # Extract class name from filename (e.g., "apple1.png" -> "apple")
                    class_name = img_file.split('.')[0]  # Remove extension
                    class_name = ''.join([c for c in class_name if not c.isdigit()])  # Remove numbers
                    
                    if not class_name:
                        class_name = "unknown"
                        
                    try:
                        img = cv2.imread(img_path)
                        if img is not None:
                            self.add_sample(img, class_name)
                            logger.info(f"Loaded {img_path} as class '{class_name}'")
                    except Exception as e:
                        logger.error(f"Error loading {img_path}: {e}")
                        
    def predict(self, image: np.ndarray) -> Recognition:
        """
        Predict the class of an image with improved confidence calculation.
        
        Args:
            image: Image as numpy array
            
        Returns:
            Recognition result with label, confidence, and scores
        """
        with self._lock:
            if not self.trained or self._actual_size == 0:
                return Recognition(
                    label="unknown",
                    confidence=0.0,
                    all_scores={},
                    embedding=np.array([]),
                    is_known=False
                )
                
            # Extract embedding
            embedding = self.extract_embedding(image)
            
            # Get k nearest neighbors and distances
            distances, indices = self.knn.kneighbors(
                embedding.reshape(1, -1), 
                n_neighbors=min(self.n_neighbors, self._actual_size)
            )
            
            # Get labels of nearest neighbors
            y_data = self.y_train[:self._actual_size]
            neighbor_labels = y_data[indices[0]]
            neighbor_distances = distances[0]
            
            # Calculate weighted voting based on distance
            # Convert cosine distance to similarity (1 - distance)
            similarities = 1 - neighbor_distances
            
            # Calculate scores for each class
            unique_labels = np.unique(y_data)
            all_scores = {}
            
            for label in unique_labels:
                label_mask = neighbor_labels == label
                if np.any(label_mask):
                    # Weighted average of similarities for this class
                    all_scores[label] = np.sum(similarities[label_mask]) / np.sum(similarities)
                else:
                    all_scores[label] = 0.0
            
            # Get prediction and confidence
            if all_scores:
                pred_label = max(all_scores.keys(), key=lambda k: all_scores[k])
                confidence = all_scores[pred_label]
                
                # Additional confidence adjustment based on distance to nearest neighbor
                # If nearest neighbor is very far, reduce confidence
                if neighbor_distances[0] > 0.5:  # Cosine distance > 0.5 means low similarity
                    confidence *= (1 - neighbor_distances[0])
            else:
                pred_label = "unknown"
                confidence = 0.0
            
            # Check if known based on adjusted confidence
            is_known = confidence >= self.confidence_threshold
            
            return Recognition(
                label=pred_label if is_known else "unknown",
                confidence=float(confidence),
                all_scores=all_scores,
                embedding=embedding,
                is_known=is_known
            )
        
    def get_known_classes(self) -> List[str]:
        """Get list of known class labels."""
        if self.trained and self._actual_size > 0:
            return list(np.unique(self.y_train[:self._actual_size]))
        return []
        
    def get_sample_count(self) -> Dict[str, int]:
        """Get count of samples per class."""
        if self._actual_size == 0:
            return {}
        counts = {}
        for label in self.y_train[:self._actual_size]:
            counts[label] = counts.get(label, 0) + 1
        return counts
        
    def save_model(self, path: Optional[str] = None):
        """Save the trained model to disk."""
        with self._lock:
            save_path = path or self.model_path
            
            # Create directory if needed
            os.makedirs(os.path.dirname(save_path), exist_ok=True)
            
            active_X = self.X_train[:self._actual_size] if self._actual_size > 0 else np.empty((0, self.embedding_dim), dtype=np.float32)
            active_y = self.y_train[:self._actual_size] if self._actual_size > 0 else np.array([], dtype=object)
            
            # Save model data with numpy arrays
            model_data = {
                'X_train': active_X,
                'y_train': active_y,
                'n_neighbors': self.n_neighbors,
                'confidence_threshold': self.confidence_threshold,
                'max_samples_per_class': self.max_samples_per_class,
                'embedding_dim': self.embedding_dim,
                'actual_size': self._actual_size
            }
            
            # Use numpy's save for better handling of arrays
            np.savez_compressed(save_path, **model_data)
                
            logger.info(f"Model saved to {save_path} ({self._actual_size} samples)")
        
    def load_model(self, path: Optional[str] = None) -> bool:
        """Load a trained model from disk."""
        with self._lock:
            load_path = path or self.model_path
            
            if not os.path.exists(load_path):
                logger.info(f"No saved model found at {load_path}")
                return False
                
            try:
                # Load numpy archive
                model_data = np.load(load_path, allow_pickle=True)
                
                loaded_X = model_data['X_train']
                loaded_y = model_data['y_train']
                self.n_neighbors = int(model_data.get('n_neighbors', self.n_neighbors))
                self.confidence_threshold = float(model_data.get('confidence_threshold', self.confidence_threshold))
                self.max_samples_per_class = int(model_data.get('max_samples_per_class', self.max_samples_per_class))
                
                # Ensure arrays are proper numpy arrays
                if not isinstance(loaded_X, np.ndarray):
                    loaded_X = np.array(loaded_X, dtype=np.float32)
                if not isinstance(loaded_y, np.ndarray):
                    loaded_y = np.array(loaded_y, dtype=object)
                
                self._actual_size = len(loaded_X)
                self._capacity = max(100, self._actual_size * 2)  # Ensure some growth capacity
                
                self.X_train = np.empty((self._capacity, self.embedding_dim), dtype=np.float32)
                self.y_train = np.empty(self._capacity, dtype=object)
                
                if self._actual_size > 0:
                    self.X_train[:self._actual_size] = loaded_X
                    self.y_train[:self._actual_size] = loaded_y
                
                # Retrain KNN
                if self._actual_size > 0:
                    self._retrain_knn()
                    
                logger.info(f"Model loaded from {load_path}. {self._actual_size} samples")
                return True
                
            except Exception as e:
                logger.error(f"Error loading model: {e}")
                return False
    
            
    def reset(self):
        """Reset the classifier, removing all training data."""
        self.X_train = np.empty((0, self.embedding_dim), dtype=np.float32)
        self.y_train = np.array([], dtype=object)
        self._capacity = 100
        self._actual_size = 0
        self.knn = KNeighborsClassifier(n_neighbors=self.n_neighbors)
        self.trained = False
        logger.info("Classifier reset")
        
    def update_confidence_threshold(self, threshold: float):
        """Update the confidence threshold for known/unknown classification."""
        self.confidence_threshold = threshold
        logger.info(f"Confidence threshold updated to {threshold}")


class AdaptiveKNNClassifier(KNNObjectClassifier):
    """
    Adaptive KNN that can learn from both successes and failures.
    Integrates with the feedback loop from Gemini API.
    """
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.feedback_history = []
        self.auto_save = True
        self.save_interval = 10  # Save after every N new samples
        
    def add_feedback_sample(self, image: np.ndarray, 
                           predicted_label: str,
                           correct_label: str,
                           source: str = "user"):
        """
        Add a sample based on feedback (correction).
        
        Args:
            image: The image that was misclassified
            predicted_label: What the model predicted
            correct_label: The correct label (from Gemini or user)
            source: Source of correction (user/gemini/manual)
        """
        # Add the corrected sample
        self.add_sample(image, correct_label)
        
        # Track feedback
        self.feedback_history.append({
            'predicted': predicted_label,
            'correct': correct_label,
            'source': source,
            'timestamp': np.datetime64('now')
        })
        
        # Auto-save if needed
        if self.auto_save and len(self.X_train) % self.save_interval == 0:
            self.save_model()
            
        logger.info(f"Learned from feedback: {predicted_label} -> {correct_label} (via {source})")
        
    def get_accuracy_stats(self) -> Dict[str, Any]:
        """Get statistics about classifier performance."""
        if not self.feedback_history:
            return {}
            
        total = len(self.feedback_history)
        correct = sum(1 for f in self.feedback_history 
                     if f['predicted'] == f['correct'])
        
        return {
            'total_feedback': total,
            'correct_predictions': correct,
            'accuracy': correct / total if total > 0 else 0,
            'unique_corrections': len(set(f['correct'] for f in self.feedback_history))
        }
