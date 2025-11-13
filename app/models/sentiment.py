"""
Sentiment Analysis Model
Loads the fine-tuned sentiment model and provides scoring functionality
"""

from pathlib import Path
from typing import Dict, List, Optional
import logging
import os

# Lazy import heavy ML dependencies
try:
    import torch
    import numpy as np
    from transformers import AutoTokenizer, AutoModelForSequenceClassification
    _ML_DEPS_AVAILABLE = True
except ImportError:
    torch = None
    np = None
    AutoTokenizer = None
    AutoModelForSequenceClassification = None
    _ML_DEPS_AVAILABLE = False

logger = logging.getLogger(__name__)

class SentimentModel:
    """Sentiment analysis model for financial text"""
    
    def __init__(self, model_path: Optional[str] = None):
        """
        Initialize the sentiment model
        
        Args:
            model_path: Path to the fine-tuned sentiment model. If not provided,
                       will read from SENTIMENT_MODEL_DIR environment variable,
                       defaulting to "models/sentiment-finetuned"
        """
        if model_path is None:
            model_path = os.getenv('SENTIMENT_MODEL_DIR', 'models/sentiment-finetuned')
        self.model_path = Path(model_path)
        self.model = None
        self.tokenizer = None
        self.label_mapping = {
            0: "negative",
            1: "neutral", 
            2: "positive"
        }
        self._load_model()
    
    def _load_model(self):
        """Load the fine-tuned model and tokenizer"""
        # Check if sentiment analysis is enabled via environment variable
        enable_sentiment = os.getenv('ENABLE_SENTIMENT_ANALYSIS', 'false').lower() in ('true', '1', 'yes')
        if not enable_sentiment:
            logger.info(
                "Sentiment analysis is disabled (ENABLE_SENTIMENT_ANALYSIS not set to true). "
                "Set ENABLE_SENTIMENT_ANALYSIS=true to enable sentiment analysis features."
            )
            return
        
        if not _ML_DEPS_AVAILABLE:
            logger.warning(
                "ML dependencies (torch, transformers) not available. "
                "Sentiment analysis via 'analyze:' prefix will not work. "
                "The app will continue to function normally for all other features. "
                "To enable sentiment analysis, install torch and transformers packages."
            )
            return
        try:
            # Check if the fine-tuned model exists and has files
            model_files = list(self.model_path.glob("*.json")) + list(self.model_path.glob("*.bin")) + list(self.model_path.glob("*.safetensors"))
            
            if not self.model_path.exists() or len(model_files) == 0:
                logger.warning(f"Fine-tuned model not found at {self.model_path}. Using base DistilBERT model.")
                # Fall back to base model
                model_name = "distilbert-base-uncased"
                self.tokenizer = AutoTokenizer.from_pretrained(model_name)
                self.model = AutoModelForSequenceClassification.from_pretrained(
                    model_name, 
                    num_labels=3,
                    id2label={0: "negative", 1: "neutral", 2: "positive"},
                    label2id={"negative": 0, "neutral": 1, "positive": 2}
                )
                logger.info("Base DistilBERT model loaded (not fine-tuned)")
            else:
                logger.info(f"Loading fine-tuned sentiment model from {self.model_path}")
                # Load fine-tuned model
                self.tokenizer = AutoTokenizer.from_pretrained(str(self.model_path))
                self.model = AutoModelForSequenceClassification.from_pretrained(str(self.model_path))
                logger.info("Fine-tuned sentiment model loaded successfully")
            
            # Set model to evaluation mode
            self.model.eval()
            
        except Exception as e:
            logger.error(f"Failed to load sentiment model: {e}")
            raise
    
    def score(self, text: str) -> Dict[str, any]:
        """
        Analyze sentiment of the given text
        
        Args:
            text: Text to analyze
            
        Returns:
            Dictionary containing:
            - label: Predicted sentiment label (negative, neutral, positive)
            - probs: List of probabilities for each class [negative, neutral, positive]
        """
        if not self.model or not self.tokenizer:
            raise RuntimeError(
                "Sentiment model not loaded. ML dependencies (torch, transformers) are not installed. "
                "Please install these packages to use sentiment analysis features."
            )
        
        try:
            # Tokenize the input text
            inputs = self.tokenizer(
                text,
                return_tensors="pt",
                truncation=True,
                padding=True,
                max_length=512
            )
            
            # Get model predictions
            with torch.no_grad():
                outputs = self.model(**inputs)
                logits = outputs.logits
                
                # Apply softmax to get probabilities
                probabilities = torch.softmax(logits, dim=-1)
                probs = probabilities.squeeze().numpy().tolist()
                
                # Get predicted class
                predicted_class = torch.argmax(logits, dim=-1).item()
                predicted_label = self.label_mapping[predicted_class]
            
            return {
                "label": predicted_label,
                "probs": probs
            }
            
        except Exception as e:
            logger.error(f"Error during sentiment analysis: {e}")
            raise

# Global instance for reuse
_sentiment_model = None

def get_sentiment_model() -> SentimentModel:
    """Get or create the global sentiment model instance"""
    global _sentiment_model
    if _sentiment_model is None:
        _sentiment_model = SentimentModel()
    return _sentiment_model

def score(text: str) -> Dict[str, any]:
    """
    Convenience function to score text sentiment
    
    Args:
        text: Text to analyze
        
    Returns:
        Dictionary containing label and probabilities
    """
    model = get_sentiment_model()
    return model.score(text)
