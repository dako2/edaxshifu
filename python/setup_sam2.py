#!/usr/bin/env python3
"""
Setup script to download and configure SAM2 for EdaxShifu integration.
"""

import os
import sys
import subprocess
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def run_command(cmd, cwd=None):
    """Run a shell command and return success status."""
    try:
        result = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
        if result.returncode != 0:
            logger.error(f"Command failed: {cmd}")
            logger.error(f"Error: {result.stderr}")
            return False
        logger.info(f"Command succeeded: {cmd}")
        return True
    except Exception as e:
        logger.error(f"Exception running command {cmd}: {e}")
        return False

def setup_sam2():
    """Download and setup SAM2 repository and models."""
    
    assets_dir = Path("assets")
    sam2_dir = assets_dir / "sam2"
    sam2_dir.mkdir(parents=True, exist_ok=True)
    
    sam2_repo_dir = Path("sam2_repo")
    if not sam2_repo_dir.exists():
        logger.info("Cloning SAM2 repository...")
        if not run_command("git clone https://github.com/facebookresearch/sam2.git sam2_repo"):
            return False
    
    logger.info("Installing SAM2 package...")
    if not run_command("pip install -e sam2_repo", cwd="."):
        logger.warning("Failed to install SAM2 package, continuing...")
    
    checkpoints_dir = sam2_dir / "checkpoints"
    checkpoints_dir.mkdir(exist_ok=True)
    
    model_url = "https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_small.pt"
    model_path = checkpoints_dir / "sam2_hiera_small.pt"
    
    if not model_path.exists():
        logger.info(f"Downloading SAM2 model to {model_path}...")
        if not run_command(f"wget -O {model_path} {model_url}"):
            logger.error("Failed to download SAM2 model")
            return False
    else:
        logger.info("SAM2 model already exists")
    
    config_src = sam2_repo_dir / "sam2_configs" / "sam2_hiera_s.yaml"
    config_dst = sam2_dir / "sam2_hiera_small.yaml"
    
    if config_src.exists() and not config_dst.exists():
        logger.info("Copying SAM2 config file...")
        if not run_command(f"cp {config_src} {config_dst}"):
            logger.warning("Failed to copy config file")
    
    logger.info("SAM2 setup completed!")
    return True

if __name__ == "__main__":
    success = setup_sam2()
    if not success:
        logger.error("SAM2 setup failed!")
        sys.exit(1)
    else:
        logger.info("SAM2 setup successful!")
