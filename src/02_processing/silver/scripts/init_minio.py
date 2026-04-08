from minio import Minio
import os

minio_client = Minio(
    "minio:9000",
    access_key=os.environ["MINIO_USER"],
    secret_key=os.environ["MINIO_PASS"],
    secure=False,
)
for bucket in ["bronze", "silver", "gold"]:
    if not minio_client.bucket_exists(bucket):
        minio_client.make_bucket(bucket)
