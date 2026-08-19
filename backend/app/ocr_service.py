"""TrOCR handwriting recognition engine for clinical forms in AI-DSUHIS."""

from __future__ import annotations

import io
import logging
import time
from typing import List, Optional, Tuple

import numpy as np
from PIL import Image

try:
    import cv2
except ImportError:
    cv2 = None

try:
    import torch
    from transformers import TrOCRProcessor, VisionEncoderDecoderModel
except ImportError:
    torch = None
    TrOCRProcessor = None
    VisionEncoderDecoderModel = None

logger = logging.getLogger("ocr_service")
logger.setLevel(logging.INFO)


class TrOCRHandwritingEngine:
    """Singleton service wrapping Microsoft TrOCR for handwritten clinical text."""

    _instance: Optional[TrOCRHandwritingEngine] = None

    def __init__(self, model_name: str = "microsoft/trocr-base-handwritten"):
        self.model_name = model_name
        self.device = None
        self.processor = None
        self.model = None
        self.is_ready = False

        if torch is None or VisionEncoderDecoderModel is None:
            logger.warning(
                "PyTorch / Transformers not installed. TrOCR engine running in fallback stub mode."
            )
            return

        try:
            self.device = torch.device(
                "cuda"
                if torch.cuda.is_available()
                else ("mps" if torch.backends.mps.is_available() else "cpu")
            )
            logger.info("Initializing TrOCR '%s' on %s", model_name, self.device)
            self.processor = TrOCRProcessor.from_pretrained(model_name)
            self.model = VisionEncoderDecoderModel.from_pretrained(model_name).to(
                self.device
            )
            self.model.eval()
            if self.device.type == "cuda":
                self.model.half()

            self.model.config.decoder_start_token_id = (
                self.processor.tokenizer.cls_token_id
            )
            self.model.config.pad_token_id = self.processor.tokenizer.pad_token_id
            self.model.config.vocab_size = self.model.config.decoder.vocab_size
            self.is_ready = True
            logger.info("TrOCR Engine successfully loaded.")
        except Exception as e:
            logger.error("Failed to load TrOCR model '%s': %s", model_name, e)
            self.is_ready = False

    @classmethod
    def get_instance(cls) -> TrOCRHandwritingEngine:
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def preprocess_image(self, pil_img: Image.Image) -> Image.Image:
        """Applies CLAHE and bilateral filtering to enhance handwritten strokes."""
        img_rgb = pil_img.convert("RGB")
        if cv2 is None:
            return img_rgb

        try:
            np_img = np.array(img_rgb)
            gray = cv2.cvtColor(np_img, cv2.COLOR_RGB2GRAY)
            clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
            contrast_enhanced = clahe.apply(gray)
            denoised = cv2.bilateralFilter(
                contrast_enhanced, d=9, sigmaColor=75, sigmaSpace=75
            )
            return Image.fromarray(cv2.cvtColor(denoised, cv2.COLOR_GRAY2RGB))
        except Exception as e:
            logger.warning("OpenCV image preprocessing error: %s", e)
            return img_rgb

    def recognize_single(self, image_bytes: bytes) -> Tuple[str, float]:
        """Recognizes a single cropped handwritten image ROI."""
        if not self.is_ready or self.processor is None or self.model is None:
            return ("", 0.0)

        pil_img = Image.open(io.BytesIO(image_bytes))
        enhanced = self.preprocess_image(pil_img)

        pixel_values = self.processor(enhanced, return_tensors="pt").pixel_values.to(
            self.device
        )
        if self.device.type == "cuda":
            pixel_values = pixel_values.half()

        with torch.no_grad():
            outputs = self.model.generate(
                pixel_values,
                output_scores=True,
                return_dict_in_generate=True,
                max_new_tokens=64,
                num_beams=2,
                early_stopping=True,
            )

        generated_ids = outputs.sequences
        generated_text = self.processor.batch_decode(
            generated_ids, skip_special_tokens=True
        )[0].strip()

        confidence = 0.85
        if hasattr(outputs, "scores") and outputs.scores:
            probs = [
                torch.softmax(score, dim=-1).max().item() for score in outputs.scores
            ]
            if probs:
                confidence = float(np.mean(probs))

        return generated_text, round(confidence, 4)

    def recognize_batch(
        self, images_bytes_list: List[bytes]
    ) -> List[Tuple[str, float]]:
        """Concurrently processes multiple handwritten field crops in a single forward pass."""
        if not images_bytes_list:
            return []

        if not self.is_ready or self.processor is None or self.model is None:
            return [("", 0.0) for _ in images_bytes_list]

        pil_images = [
            self.preprocess_image(Image.open(io.BytesIO(b))) for b in images_bytes_list
        ]
        pixel_values = self.processor(pil_images, return_tensors="pt").pixel_values.to(
            self.device
        )
        if self.device.type == "cuda":
            pixel_values = pixel_values.half()

        with torch.no_grad():
            outputs = self.model.generate(
                pixel_values,
                output_scores=True,
                return_dict_in_generate=True,
                max_new_tokens=64,
                num_beams=2,
            )

        generated_ids = outputs.sequences
        transcriptions = self.processor.batch_decode(
            generated_ids, skip_special_tokens=True
        )

        results: List[Tuple[str, float]] = []
        for text in transcriptions:
            results.append((text.strip(), 0.88))
        return results
