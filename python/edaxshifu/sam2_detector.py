import cv2
import numpy as np
import torch
from typing import List, Dict, Tuple, Optional
import logging
import os
import sys

logger = logging.getLogger(__name__)


class SAM2Detector:
    """SAM2 segmentation detector for real-time inference."""
    
    _model_cache = {}
    
    def __init__(self, model_config: str = "sam2_hiera_s.yaml", 
                 checkpoint_path: str = "assets/sam2/checkpoints/sam2_hiera_small.pt",
                 conf_threshold: float = 0.5):
        """
        Initialize SAM2 detector.
        
        Args:
            model_config: SAM2 model configuration file
            checkpoint_path: Path to SAM2 model checkpoint
            conf_threshold: Confidence threshold for segmentation
        """
        self.model_config = model_config
        self.checkpoint_path = checkpoint_path
        self.conf_threshold = conf_threshold
        self.predictor = None
        self.sam2_available = False
        self.load_model()
    
    def _check_sam2_availability(self) -> bool:
        """Check if SAM2 is available and properly installed."""
        try:
            import sam2
            from sam2.build_sam import build_sam2
            from sam2.sam2_image_predictor import SAM2ImagePredictor
            return True
        except ImportError as e:
            logger.warning(f"SAM2 not available: {e}")
            return False
    
    def load_model(self) -> bool:
        """Load SAM2 model with caching."""
        try:
            if not self._check_sam2_availability():
                logger.error("SAM2 dependencies not available")
                return False
            
            from sam2.build_sam import build_sam2
            from sam2.sam2_image_predictor import SAM2ImagePredictor
            
            cache_key = f"{self.model_config}_{self.checkpoint_path}"
            if cache_key in self._model_cache:
                self.predictor = self._model_cache[cache_key]
                self.sam2_available = True
                logger.info(f"SAM2 model loaded from cache")
                return True
            
            if not os.path.exists(self.checkpoint_path):
                logger.error(f"SAM2 checkpoint not found: {self.checkpoint_path}")
                return False
            
            sam2_model = build_sam2(self.model_config, self.checkpoint_path)
            self.predictor = SAM2ImagePredictor(sam2_model)
            self._model_cache[cache_key] = self.predictor
            self.sam2_available = True
            logger.info(f"SAM2 model loaded and cached: {self.checkpoint_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to load SAM2 model: {e}")
            self.sam2_available = False
            return False
    
    def detect(self, frame: np.ndarray, input_points: Optional[np.ndarray] = None, 
               input_labels: Optional[np.ndarray] = None) -> List[Dict]:
        """
        Perform segmentation on frame.
        
        Args:
            frame: Input image/frame as numpy array
            input_points: Point prompts for segmentation (Nx2 array)
            input_labels: Labels for points (1=foreground, 0=background)
            
        Returns:
            List of segmentation results, each containing:
            - mask: Binary segmentation mask
            - confidence: Segmentation confidence score
            - bbox: Bounding box of the segmented region
        """
        if not self.sam2_available or self.predictor is None:
            logger.warning("SAM2 model not available")
            return []
        
        try:
            self.predictor.set_image(frame)
            
            if input_points is None:
                h, w = frame.shape[:2]
                input_points = np.array([[w//2, h//2]])
                input_labels = np.array([1])
            
            if input_labels is None:
                input_labels = np.ones(len(input_points))
            
            masks, scores, logits = self.predictor.predict(
                point_coords=input_points,
                point_labels=input_labels,
                multimask_output=True
            )
            
            results = []
            for i, (mask, score) in enumerate(zip(masks, scores)):
                if score > self.conf_threshold:
                    bbox = self._mask_to_bbox(mask)
                    
                    results.append({
                        'mask': mask,
                        'confidence': float(score),
                        'bbox': bbox,
                        'mask_id': i
                    })
            
            return results
            
        except Exception as e:
            logger.error(f"SAM2 detection error: {e}")
            return []
    
    def _mask_to_bbox(self, mask: np.ndarray) -> Tuple[int, int, int, int]:
        """Convert binary mask to bounding box."""
        if not np.any(mask):
            return (0, 0, 0, 0)
        
        rows = np.any(mask, axis=1)
        cols = np.any(mask, axis=0)
        
        y_min, y_max = np.where(rows)[0][[0, -1]]
        x_min, x_max = np.where(cols)[0][[0, -1]]
        
        return (int(x_min), int(y_min), int(x_max - x_min), int(y_max - y_min))
    
    def draw_segmentation(self, frame: np.ndarray, results: List[Dict], 
                         alpha: float = 0.5) -> np.ndarray:
        """
        Draw segmentation masks on frame.
        
        Args:
            frame: Input frame
            results: List of segmentation results from detect()
            alpha: Transparency for mask overlay
            
        Returns:
            Frame with drawn segmentation masks
        """
        if not results:
            return frame
        
        overlay = frame.copy()
        
        colors = [
            (255, 0, 0),    # Red
            (0, 255, 0),    # Green
            (0, 0, 255),    # Blue
            (255, 255, 0),  # Yellow
            (255, 0, 255),  # Magenta
            (0, 255, 255),  # Cyan
        ]
        
        for i, result in enumerate(results):
            mask = result['mask']
            confidence = result['confidence']
            bbox = result['bbox']
            
            color = colors[i % len(colors)]
            
            overlay[mask] = color
            
            # Draw bounding box
            if bbox and len(bbox) == 4:
                x, y, w, h = bbox
                cv2.rectangle(frame, (x, y), (x + w, y + h), color, 2)
                
                label = f"Seg: {confidence:.2f}"
                label_size, _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
                cv2.rectangle(frame, (x, y - label_size[1] - 10), 
                             (x + label_size[0], y), color, -1)
                cv2.putText(frame, label, (x, y - 5), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        
        result_frame = cv2.addWeighted(frame, 1 - alpha, overlay, alpha, 0)
        
        return result_frame
    
    def segment_from_bbox(self, frame: np.ndarray, bbox: Tuple[int, int, int, int]) -> List[Dict]:
        """
        Segment object using bounding box as prompt.
        
        Args:
            frame: Input frame
            bbox: Bounding box (x, y, width, height)
            
        Returns:
            List of segmentation results
        """
        if not self.sam2_available:
            return []
        
        x, y, w, h = bbox
        center_x = x + w // 2
        center_y = y + h // 2
        
        input_points = np.array([[center_x, center_y]])
        input_labels = np.array([1])  # Foreground
        
        return self.detect(frame, input_points, input_labels)
