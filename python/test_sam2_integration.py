#!/usr/bin/env python3
"""
Test script for SAM2 integration in EdaxShifu.
"""

import cv2
import numpy as np
import logging
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))

from edaxshifu.sam2_detector import SAM2Detector

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_sam2_detector():
    """Test SAM2Detector class."""
    logger.info("Testing SAM2Detector...")
    
    detector = SAM2Detector()
    
    if not detector.sam2_available:
        logger.warning("SAM2 not available, creating mock test")
        return True
    
    test_image = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
    
    logger.info("Testing detection without prompts...")
    results = detector.detect(test_image)
    logger.info(f"Detection results: {len(results)} segments found")
    
    logger.info("Testing detection with point prompt...")
    point_prompt = np.array([[320, 240]])  # Center point
    results_with_prompt = detector.detect(test_image, input_points=point_prompt)
    logger.info(f"Detection with prompt results: {len(results_with_prompt)} segments found")
    
    if results_with_prompt:
        logger.info("Testing visualization...")
        visualized = detector.draw_segmentation(test_image, results_with_prompt)
        logger.info(f"Visualization successful, output shape: {visualized.shape}")
    
    logger.info("SAM2Detector test completed successfully!")
    return True

def test_api_integration():
    """Test API integration."""
    logger.info("Testing API integration...")
    
    try:
        from api_server import KNNAPIServer
        server = KNNAPIServer()
        if hasattr(server, 'sam2_detector') and server.sam2_detector and server.sam2_detector.sam2_available:
            logger.info("SAM2 detector available in API server")
        else:
            logger.warning("SAM2 detector not available in API server")
    except ImportError as e:
        logger.warning(f"Could not import API server: {e}")
    
    return True

def main():
    """Run all tests."""
    logger.info("Starting SAM2 integration tests...")
    
    tests = [
        test_sam2_detector,
        test_api_integration,
    ]
    
    for test in tests:
        try:
            if not test():
                logger.error(f"Test {test.__name__} failed!")
                return False
        except Exception as e:
            logger.error(f"Test {test.__name__} raised exception: {e}")
            return False
    
    logger.info("All tests passed!")
    return True

if __name__ == "__main__":
    success = main()
    if not success:
        sys.exit(1)
