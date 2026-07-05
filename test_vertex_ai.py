#!/usr/bin/env python3
"""Test script for Google Gen AI Enterprise (Vertex AI).

Prerequisites:
  pip install --upgrade google-genai
  gcloud auth application-default login

Usage:
  python3 test_vertex_ai.py
"""

from google import genai

# ── Configuration ───────────────────────────────────────────────────────────
PROJECT_ID = "still-algebra-501109-n0"
LOCATION   = "us"
MODEL_ID   = "gemini-3.5-flash"
# ─────────────────────────────────────────────────────────────────────────────

def test_enterprise():
    # 1. Initialize client for Google Cloud Enterprise
    client = genai.Client(
        enterprise=True,         # Google Enterprise Agent Platform
        project=PROJECT_ID,
        location=LOCATION
    )

    # 2. Call the Gemini Flash model
    response = client.models.generate_content(
        model=MODEL_ID,
        contents="Say 'Google Enterprise AI is working!' and nothing else."
    )

    # 3. Output the result
    print("Model reply:", response.text)
    print("✅ SUCCESS — Google Enterprise AI is reachable and responding.")


if __name__ == "__main__":
    try:
        test_enterprise()
    except Exception as e:
        print(f"❌ FAILED: {e}")
