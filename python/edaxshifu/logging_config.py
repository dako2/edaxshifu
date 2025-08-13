"""
Centralized logging configuration for EdaxShifu.
"""

import logging
import sys
from datetime import datetime
from typing import Optional


class EdaxShifuFormatter(logging.Formatter):
    """Custom formatter for EdaxShifu logging."""
    
    def __init__(self):
        super().__init__()
        
    def format(self, record):
        timestamp = datetime.fromtimestamp(record.created).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
        level = record.levelname
        module = record.name.split('.')[-1] if '.' in record.name else record.name
        message = record.getMessage()
        
        formatted = f"[{timestamp}] [{level:8}] [{module:20}] - {message}"
        
        if record.exc_info:
            formatted += "\n" + self.formatException(record.exc_info)
            
        return formatted


def setup_logging(level: str = "INFO", log_file: Optional[str] = None) -> logging.Logger:
    """
    Setup centralized logging for EdaxShifu.
    
    Args:
        level: Logging level (DEBUG, INFO, WARNING, ERROR)
        log_file: Optional file to write logs to
        
    Returns:
        Configured logger
    """
    numeric_level = getattr(logging, level.upper(), logging.INFO)
    
    root_logger = logging.getLogger()
    root_logger.setLevel(numeric_level)
    
    if root_logger.handlers:
        root_logger.handlers.clear()
    
    formatter = EdaxShifuFormatter()
    
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(numeric_level)
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)
    
    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(numeric_level)
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)
    
    logger = logging.getLogger("edaxshifu")
    logger.info(f"Logging initialized at level {level}")
    
    return logger


def get_logger(name: str) -> logging.Logger:
    """Get a logger for a specific module."""
    return logging.getLogger(f"edaxshifu.{name}")
