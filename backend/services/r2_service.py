import io
import os
import boto3
from botocore.client import Config as BotoConfig
from typing import Optional, Dict, Any, Tuple
from config import Config

class R2Service:
    """
    Cloudflare R2 Object Storage Service (S3-compatible API).
    Provides resilient upload, download, and streaming for media files (images, videos, audio, etc.).
    """
    _s3_client = None

    @classmethod
    def get_client(cls):
        if cls._s3_client is None:
            cls._s3_client = boto3.client(
                's3',
                endpoint_url=Config.R2_ENDPOINT_URL,
                aws_access_key_id=Config.R2_ACCESS_KEY_ID,
                aws_secret_access_key=Config.R2_SECRET_ACCESS_KEY,
                config=BotoConfig(signature_version='s3v4'),
                region_name='auto'
            )
        return cls._s3_client

    @classmethod
    def upload_media(
        cls,
        file_bytes: bytes,
        filename: str,
        content_type: str = "application/octet-stream",
        object_key: Optional[str] = None
    ) -> Optional[str]:
        """
        Uploads a media payload (image, video, audio) directly to Cloudflare R2 bucket.
        Returns the object key upon success, or None on failure.
        """
        key = object_key or f"media/{filename}"
        try:
            s3 = cls.get_client()
            s3.put_object(
                Bucket=Config.R2_BUCKET_NAME,
                Key=key,
                Body=file_bytes,
                ContentType=content_type
            )
            return key
        except Exception as e:
            print(f"[R2Service] Upload error for key '{key}': {e}")
            return None

    @classmethod
    def get_media_bytes(cls, object_key: str) -> Optional[bytes]:
        """
        Retrieves the complete binary payload for an object from Cloudflare R2.
        """
        try:
            s3 = cls.get_client()
            response = s3.get_object(
                Bucket=Config.R2_BUCKET_NAME,
                Key=object_key
            )
            return response['Body'].read()
        except Exception as e:
            print(f"[R2Service] Fetch error for key '{object_key}': {e}")
            return None

    @classmethod
    def get_media_range(cls, object_key: str, byte_range: Optional[str] = None) -> Optional[Tuple[bytes, int, str]]:
        """
        Retrieves bytes for range requests (video streaming).
        Returns tuple: (content_bytes, total_size, content_type)
        """
        try:
            s3 = cls.get_client()
            kwargs = {
                "Bucket": Config.R2_BUCKET_NAME,
                "Key": object_key
            }
            if byte_range:
                kwargs["Range"] = byte_range

            response = s3.get_object(**kwargs)
            content = response['Body'].read()
            total_size = response.get('ContentLength', len(content))
            content_type = response.get('ContentType', 'application/octet-stream')
            return content, total_size, content_type
        except Exception as e:
            print(f"[R2Service] Range fetch error for key '{object_key}': {e}")
            return None

    @classmethod
    def delete_media(cls, object_key: str) -> bool:
        """
        Deletes an object from Cloudflare R2.
        """
        try:
            s3 = cls.get_client()
            s3.delete_object(
                Bucket=Config.R2_BUCKET_NAME,
                Key=object_key
            )
            return True
        except Exception as e:
            print(f"[R2Service] Delete error for key '{object_key}': {e}")
            return False
