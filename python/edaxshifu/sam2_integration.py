import logging
from typing import Dict, Any, List, Optional
import numpy as np
from .sam2_detector import SAM2Detector

logger = logging.getLogger(__name__)


def add_sam2_to_interface(interface_instance):
    """Add SAM2 functionality to existing UnifiedEdaxShifu interface."""
    
    interface_instance.sam2_detector = SAM2Detector()
    
    interface_instance.detection_modes['sam2'] = False
    
    interface_instance.stats['sam2_segments'] = 0
    
    logger.info("SAM2 integration added to interface")


def process_sam2_segmentation(sam2_detector: SAM2Detector, frame: np.ndarray, 
                             detections: Optional[List[Dict]] = None) -> tuple:
    """Process SAM2 segmentation and return results and updated frame."""
    sam2_results = []
    
    if detections:
        for det in detections:
            bbox = det.get('bbox', [])
            if len(bbox) == 4:
                x, y, w, h = bbox
                point_prompt = np.array([[x + w//2, y + h//2]])
                sam2_result = sam2_detector.detect(frame, input_points=point_prompt)
                sam2_results.extend(sam2_result)
    else:
        sam2_results = sam2_detector.detect(frame)
    
    if sam2_results:
        frame = sam2_detector.draw_segmentation(frame, sam2_results)
    
    return sam2_results, frame


def create_sam2_api_endpoints(api_server_instance):
    """Add SAM2 endpoints to existing API server."""
    
    api_server_instance.sam2_detector = SAM2Detector()
    
    logger.info("SAM2 API endpoints added to server")
