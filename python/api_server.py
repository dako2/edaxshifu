#!/usr/bin/env python3
"""
EdaxShifu KNN API Server
Exposes the trained KNN model for inference via REST API endpoints.
"""

import os
import sys
import logging
import asyncio
from typing import Optional, Dict, Any, List
from datetime import datetime
import base64
import io

import uvicorn
from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import cv2
import numpy as np
from PIL import Image

from edaxshifu.knn_classifier import AdaptiveKNNClassifier, Recognition
from edaxshifu.sam2_detector import SAM2Detector
from edaxshifu.logging_config import get_logger

logger = get_logger("api_server")

class PredictionRequest(BaseModel):
    image_base64: str
    confidence_threshold: Optional[float] = None

class PredictionResponse(BaseModel):
    label: str
    confidence: float
    is_known: bool
    all_scores: Dict[str, float]
    timestamp: str

class ModelStatsResponse(BaseModel):
    known_classes: List[str]
    total_samples: int
    sample_counts: Dict[str, int]
    confidence_threshold: float
    model_trained: bool

class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    sam2_available: bool
    known_classes_count: int
    total_samples: int

class SegmentationRequest(BaseModel):
    image_base64: str
    input_points: Optional[List[List[int]]] = None
    input_labels: Optional[List[int]] = None

class SegmentationResponse(BaseModel):
    masks: List[Dict]
    timestamp: str

class AIAnnotationRequest(BaseModel):
    image_base64: str
    yolo_detections: Optional[List[str]] = None
    knn_prediction: Optional[str] = None
    knn_confidence: Optional[float] = None

class AIAnnotationResponse(BaseModel):
    label: str
    confidence: float
    success: bool
    processing_time: Optional[float] = None
    error_message: Optional[str] = None
    bounding_boxes: Optional[List[Dict[str, Any]]] = None

class BatchAnnotationRequest(BaseModel):
    images_base64: List[str]
    
class BatchAnnotationResponse(BaseModel):
    results: List[AIAnnotationResponse]
    total_processed: int
    total_successful: int

class KNNAPIServer:
    """FastAPI server for KNN model inference."""
    
    def __init__(self, model_path: str = "models/knn_classifier.npz"):
        self.model_path = model_path
        self.knn_classifier = None
        self.sam2_detector = None
        self.gemini_annotator = None
        self.app = FastAPI(
            title="EdaxShifu KNN API with SAM2 Support",
            description="REST API for KNN object recognition inference, AI annotation, and SAM2 segmentation",
            version="1.1.0"
        )
        
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        
        self._setup_routes()
        self._load_model()
        self._load_sam2_detector()
        self._load_ai_annotator()
    
    def _load_model(self):
        """Load the trained KNN model."""
        try:
            self.knn_classifier = AdaptiveKNNClassifier(
                model_path=self.model_path,
                confidence_threshold=0.6
            )
            
            # Try to load existing model
            if os.path.exists(self.model_path):
                success = self.knn_classifier.load_model()
                if success:
                    logger.info(f"Loaded KNN model from {self.model_path}")
                    logger.info(f"Known classes: {self.knn_classifier.get_known_classes()}")
                else:
                    logger.warning("Failed to load existing model, starting fresh")
            else:
                logger.info("No existing model found, starting fresh")
                
        except Exception as e:
            logger.error(f"Error initializing KNN classifier: {e}")
            logger.debug(f"KNN initialization error details: {type(e).__name__}: {str(e)}")
            raise
    
    def _load_sam2_detector(self):
        """Load the SAM2 detector."""
        try:
            self.sam2_detector = SAM2Detector()
            logger.info("SAM2 detector initialized")
        except Exception as e:
            logger.warning(f"Failed to load SAM2 detector: {e}")
            self.sam2_detector = None
    
    def _load_ai_annotator(self):
        """Load the AI annotator for enhanced annotation features."""
        try:
            from edaxshifu.annotators import AnnotatorFactory
            self.gemini_annotator = AnnotatorFactory.create_gemini_annotator()
            if self.gemini_annotator.is_available():
                logger.info("AI annotator (Gemini) initialized and available")
            else:
                logger.info("AI annotator initialized but API key not available")
                logger.debug("Set GEMINI_API_KEY environment variable to enable AI annotation endpoints")
        except Exception as e:
            logger.warning(f"Failed to initialize AI annotator: {e}")
            logger.debug(f"AI annotator initialization error: {type(e).__name__}: {str(e)}")
            self.gemini_annotator = None
    
    def _setup_routes(self):
        """Setup FastAPI routes."""
        
        @self.app.get("/", response_model=HealthResponse)
        async def health_check():
            """Health check endpoint."""
            if not self.knn_classifier:
                return HealthResponse(
                    status="error",
                    model_loaded=False,
                    sam2_available=self.sam2_detector is not None and self.sam2_detector.sam2_available,
                    known_classes_count=0,
                    total_samples=0
                )
            
            return HealthResponse(
                status="healthy",
                model_loaded=self.knn_classifier.trained,
                sam2_available=self.sam2_detector is not None and self.sam2_detector.sam2_available,
                known_classes_count=len(self.knn_classifier.get_known_classes()),
                total_samples=len(self.knn_classifier.X_train) if self.knn_classifier.X_train is not None else 0
            )

        @self.app.post("/predict/sam2", response_model=SegmentationResponse)
        async def predict_sam2_image(request: SegmentationRequest):
            """Predict segmentation from base64 encoded image."""
            if self.sam2_detector is None or not self.sam2_detector.sam2_available:
                raise HTTPException(status_code=503, detail="SAM2 model not available")
            
            try:
                image_data = base64.b64decode(request.image_base64)
                image = Image.open(io.BytesIO(image_data))
                image_array = np.array(image)
                
                if len(image_array.shape) == 3 and image_array.shape[2] == 3:
                    image_array = cv2.cvtColor(image_array, cv2.COLOR_RGB2BGR)
                
                input_points = None
                input_labels = None
                
                if request.input_points:
                    input_points = np.array(request.input_points)
                if request.input_labels:
                    input_labels = np.array(request.input_labels)
                
                results = self.sam2_detector.detect(image_array, input_points=input_points, input_labels=input_labels)
                
                serializable_results = []
                for result in results:
                    mask = result['mask']
                    mask_coords = np.where(mask)
                    serializable_results.append({
                        'confidence': result['confidence'],
                        'bbox': result['bbox'],
                        'mask_coords': [mask_coords[0].tolist(), mask_coords[1].tolist()],
                        'mask_shape': mask.shape,
                        'mask_id': result.get('mask_id', 0)
                    })
                
                return SegmentationResponse(
                    masks=serializable_results,
                    timestamp=datetime.now().isoformat()
                )
            except Exception as e:
                logger.error(f"SAM2 prediction error: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/predict/sam2/upload")
        async def predict_sam2_upload(
            file: UploadFile = File(...),
            input_points: Optional[str] = Form(None),
            input_labels: Optional[str] = Form(None)
        ):
            """Predict segmentation from uploaded image file."""
            if self.sam2_detector is None or not self.sam2_detector.sam2_available:
                raise HTTPException(status_code=503, detail="SAM2 model not available")
            
            try:
                contents = await file.read()
                image = Image.open(io.BytesIO(contents))
                image_array = np.array(image)
                
                if len(image_array.shape) == 3 and image_array.shape[2] == 3:
                    image_array = cv2.cvtColor(image_array, cv2.COLOR_RGB2BGR)
                
                points = None
                labels = None
                
                if input_points:
                    try:
                        points = np.array(eval(input_points))
                    except:
                        logger.warning("Failed to parse input_points")
                
                if input_labels:
                    try:
                        labels = np.array(eval(input_labels))
                    except:
                        logger.warning("Failed to parse input_labels")
                
                results = self.sam2_detector.detect(image_array, input_points=points, input_labels=labels)
                
                serializable_results = []
                for result in results:
                    mask = result['mask']
                    mask_coords = np.where(mask)
                    serializable_results.append({
                        'confidence': result['confidence'],
                        'bbox': result['bbox'],
                        'mask_coords': [mask_coords[0].tolist(), mask_coords[1].tolist()],
                        'mask_shape': mask.shape,
                        'mask_id': result.get('mask_id', 0)
                    })
                
                return SegmentationResponse(
                    masks=serializable_results,
                    timestamp=datetime.now().isoformat()
                )
            except Exception as e:
                logger.error(f"SAM2 upload prediction error: {e}")
                raise HTTPException(status_code=500, detail=str(e))
        
        @self.app.post("/predict", response_model=PredictionResponse)
        async def predict_image(request: PredictionRequest):
            """Predict object class from base64 encoded image."""
            if not self.knn_classifier or not self.knn_classifier.trained:
                raise HTTPException(
                    status_code=503,
                    detail="KNN model not loaded or not trained"
                )
            
            try:
                image_data = base64.b64decode(request.image_base64)
                image = Image.open(io.BytesIO(image_data))
                
                img_array = np.array(image)
                if len(img_array.shape) == 2:  # Grayscale
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_GRAY2BGR)
                elif img_array.shape[2] == 4:  # RGBA
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_RGBA2BGR)
                else:  # RGB
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
                
                if request.confidence_threshold is not None:
                    original_threshold = self.knn_classifier.confidence_threshold
                    self.knn_classifier.confidence_threshold = request.confidence_threshold
                
                recognition = self.knn_classifier.predict(img_array)
                
                if request.confidence_threshold is not None:
                    self.knn_classifier.confidence_threshold = original_threshold
                
                return PredictionResponse(
                    label=recognition.label,
                    confidence=recognition.confidence,
                    is_known=recognition.is_known,
                    all_scores=recognition.all_scores,
                    timestamp=datetime.now().isoformat()
                )
                
            except Exception as e:
                logger.error(f"Prediction error: {e}")
                raise HTTPException(
                    status_code=400,
                    detail=f"Error processing image: {str(e)}"
                )
        
        @self.app.post("/predict/upload", response_model=PredictionResponse)
        async def predict_upload(
            file: UploadFile = File(...),
            confidence_threshold: Optional[float] = Form(None)
        ):
            """Predict object class from uploaded image file."""
            if not self.knn_classifier or not self.knn_classifier.trained:
                raise HTTPException(
                    status_code=503,
                    detail="KNN model not loaded or not trained"
                )
            
            try:
                contents = await file.read()
                image = Image.open(io.BytesIO(contents))
                
                img_array = np.array(image)
                if len(img_array.shape) == 2:  # Grayscale
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_GRAY2BGR)
                elif img_array.shape[2] == 4:  # RGBA
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_RGBA2BGR)
                else:  # RGB
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
                
                if confidence_threshold is not None:
                    original_threshold = self.knn_classifier.confidence_threshold
                    self.knn_classifier.confidence_threshold = confidence_threshold
                
                recognition = self.knn_classifier.predict(img_array)
                
                if confidence_threshold is not None:
                    self.knn_classifier.confidence_threshold = original_threshold
                
                return PredictionResponse(
                    label=recognition.label,
                    confidence=recognition.confidence,
                    is_known=recognition.is_known,
                    all_scores=recognition.all_scores,
                    timestamp=datetime.now().isoformat()
                )
                
            except Exception as e:
                logger.error(f"Upload prediction error: {e}")
                raise HTTPException(
                    status_code=400,
                    detail=f"Error processing uploaded file: {str(e)}"
                )
        
        @self.app.get("/model/stats", response_model=ModelStatsResponse)
        async def get_model_stats():
            """Get model statistics and information."""
            if not self.knn_classifier:
                raise HTTPException(
                    status_code=503,
                    detail="KNN model not loaded"
                )
            
            return ModelStatsResponse(
                known_classes=self.knn_classifier.get_known_classes(),
                total_samples=len(self.knn_classifier.X_train) if self.knn_classifier.X_train is not None else 0,
                sample_counts=self.knn_classifier.get_sample_count(),
                confidence_threshold=self.knn_classifier.confidence_threshold,
                model_trained=self.knn_classifier.trained
            )
        
        @self.app.post("/model/reload")
        async def reload_model():
            """Reload the model from disk (useful after new training)."""
            try:
                if self.knn_classifier:
                    success = self.knn_classifier.load_model()
                    if success:
                        return {
                            "status": "success",
                            "message": "Model reloaded successfully",
                            "known_classes": self.knn_classifier.get_known_classes(),
                            "total_samples": len(self.knn_classifier.X_train) if self.knn_classifier.X_train is not None else 0
                        }
                    else:
                        raise HTTPException(
                            status_code=500,
                            detail="Failed to reload model"
                        )
                else:
                    raise HTTPException(
                        status_code=503,
                        detail="KNN classifier not initialized"
                    )
            except Exception as e:
                logger.error(f"Model reload error: {e}")
                raise HTTPException(
                    status_code=500,
                    detail=f"Error reloading model: {str(e)}"
                )
        
        @self.app.put("/model/confidence")
        async def update_confidence_threshold(threshold: float):
            """Update the confidence threshold for predictions."""
            if not self.knn_classifier:
                raise HTTPException(
                    status_code=503,
                    detail="KNN model not loaded"
                )
            
            if not 0.0 <= threshold <= 1.0:
                raise HTTPException(
                    status_code=400,
                    detail="Confidence threshold must be between 0.0 and 1.0"
                )
            
            self.knn_classifier.update_confidence_threshold(threshold)
            return {
                "status": "success",
                "message": f"Confidence threshold updated to {threshold}",
                "new_threshold": threshold
            }
        
        @self.app.post("/annotate/ai", response_model=AIAnnotationResponse)
        async def ai_annotate_image(request: AIAnnotationRequest):
            """Get AI annotation for an image using Gemini."""
            if not self.gemini_annotator or not self.gemini_annotator.is_available():
                raise HTTPException(
                    status_code=503,
                    detail="AI annotator not available (check GEMINI_API_KEY)"
                )
            
            try:
                from edaxshifu.annotators import AnnotationRequest
                
                image_data = base64.b64decode(request.image_base64)
                image = Image.open(io.BytesIO(image_data))
                
                img_array = np.array(image)
                if len(img_array.shape) == 2:  # Grayscale
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_GRAY2BGR)
                elif img_array.shape[2] == 4:  # RGBA
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_RGBA2BGR)
                else:  # RGB
                    img_array = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
                
                # Create annotation request
                annotation_request = AnnotationRequest(
                    image=img_array,
                    image_path="",
                    metadata={},
                    yolo_detections=request.yolo_detections or [],
                    knn_prediction=request.knn_prediction,
                    knn_confidence=request.knn_confidence,
                    timestamp=datetime.now().isoformat()
                )
                
                # Get AI annotation
                result = self.gemini_annotator.annotate(annotation_request)
                
                logger.info(f"AI annotation via API: {result.label} (success: {result.success})")
                
                return AIAnnotationResponse(
                    label=result.label,
                    confidence=result.confidence,
                    success=result.success,
                    processing_time=result.processing_time,
                    error_message=result.error_message,
                    bounding_boxes=result.bounding_boxes
                )
                
            except Exception as e:
                logger.error(f"AI annotation API error: {e}")
                raise HTTPException(
                    status_code=400,
                    detail=f"Error processing AI annotation: {str(e)}"
                )
        
        @self.app.post("/annotate/batch", response_model=BatchAnnotationResponse)
        async def batch_ai_annotate(request: BatchAnnotationRequest):
            """Batch AI annotation for multiple images."""
            if not self.gemini_annotator or not self.gemini_annotator.is_available():
                raise HTTPException(
                    status_code=503,
                    detail="AI annotator not available (check GEMINI_API_KEY)"
                )
            
            try:
                from edaxshifu.annotators import AnnotationRequest
                
                results = []
                successful = 0
                
                for i, image_base64 in enumerate(request.images_base64):
                    try:
                        image_data = base64.b64decode(image_base64)
                        image = Image.open(io.BytesIO(image_data))
                        
                        img_array = np.array(image)
                        if len(img_array.shape) == 2:  # Grayscale
                            img_array = cv2.cvtColor(img_array, cv2.COLOR_GRAY2BGR)
                        elif img_array.shape[2] == 4:  # RGBA
                            img_array = cv2.cvtColor(img_array, cv2.COLOR_RGBA2BGR)
                        else:  # RGB
                            img_array = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
                        
                        # Create annotation request
                        annotation_request = AnnotationRequest(
                            image=img_array,
                            image_path=f"batch_image_{i}",
                            metadata={},
                            yolo_detections=[],
                            knn_prediction=None,
                            knn_confidence=0.0,
                            timestamp=datetime.now().isoformat()
                        )
                        
                        # Get AI annotation
                        result = self.gemini_annotator.annotate(annotation_request)
                        
                        if result.success:
                            successful += 1
                        
                        results.append(AIAnnotationResponse(
                            label=result.label,
                            confidence=result.confidence,
                            success=result.success,
                            processing_time=result.processing_time,
                            error_message=result.error_message,
                            bounding_boxes=result.bounding_boxes
                        ))
                        
                    except Exception as e:
                        logger.warning(f"Batch annotation failed for image {i}: {e}")
                        results.append(AIAnnotationResponse(
                            label="error",
                            confidence=0.0,
                            success=False,
                            error_message=str(e)
                        ))
                
                logger.info(f"Batch AI annotation completed: {successful}/{len(request.images_base64)} successful")
                
                return BatchAnnotationResponse(
                    results=results,
                    total_processed=len(request.images_base64),
                    total_successful=successful
                )
                
            except Exception as e:
                logger.error(f"Batch AI annotation error: {e}")
                raise HTTPException(
                    status_code=400,
                    detail=f"Error processing batch annotation: {str(e)}"
                )
        
        @self.app.get("/annotate/status")
        async def ai_annotator_status():
            """Check AI annotator availability and status."""
            if not self.gemini_annotator:
                return {
                    "available": False,
                    "status": "not_initialized",
                    "message": "AI annotator not initialized"
                }
            
            available = self.gemini_annotator.is_available()
            model_info = self.gemini_annotator.get_model_info()
            stats = self.gemini_annotator.get_stats()
            
            return {
                "available": available,
                "status": "ready" if available else "api_key_missing",
                "message": "AI annotator ready" if available else "API key not configured",
                "model_info": model_info,
                "stats": stats
            }

def create_app(model_path: str = "models/knn_classifier.npz") -> FastAPI:
    """Create and configure the FastAPI app."""
    server = KNNAPIServer(model_path)
    return server.app

def main():
    """Run the API server."""
    import argparse
    
    parser = argparse.ArgumentParser(description="EdaxShifu KNN API Server")
    parser.add_argument(
        "--host",
        type=str,
        default="0.0.0.0",
        help="Host to bind to (default: 0.0.0.0 for network access)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="Port to bind to (default: 8000)"
    )
    parser.add_argument(
        "--model-path",
        type=str,
        default="models/knn_classifier.npz",
        help="Path to KNN model file"
    )
    parser.add_argument(
        "--reload",
        action="store_true",
        help="Enable auto-reload for development"
    )
    
    args = parser.parse_args()
    
    print("🎯 EdaxShifu KNN API Server")
    print("=" * 50)
    print(f"📡 Host: {args.host}")
    print(f"🔌 Port: {args.port}")
    print(f"🧠 Model: {args.model_path}")
    print(f"🌐 API Docs: http://{args.host}:{args.port}/docs")
    print("=" * 50)
    
    app = create_app(args.model_path)
    
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info"
    )

if __name__ == "__main__":
    main()
