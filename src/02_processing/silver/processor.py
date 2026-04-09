from minio import Minio
from db import get_connection
import os
import uuid
from xml.etree import ElementTree as ET

minio_client = Minio(
    "minio:9000",
    access_key=os.environ["MINIO_USER"],
    secret_key=os.environ["MINIO_PASS"],
    secure=False,
)


def split_into_sections(xml_content: str) -> list[str]:
    # TODO: implement your actual XML parsing logic
    root = ET.fromstring(xml_content)
    sections = []
    for elem in root.iter("section"):
        if elem.text:
            sections.append(elem.text.strip())
    return (
        sections if sections else [xml_content]
    )  # fallback: treat whole file as one section


def analyze_sentiment(text: str) -> tuple[str, float]:
    # TODO: replace with your actual sentiment model
    return "neutral", 0.5


def analyze_topics(text: str) -> list[str]:
    # TODO: replace with your actual topic model
    return ["unknown"]


def process_episode(xml_path: str, audio_path: str):
    # 1. Pull XML from MinIO
    response = minio_client.get_object("bronze", xml_path)
    xml_content = response.read().decode("utf-8")

    # 2. Parse + split into sections
    sections = split_into_sections(xml_content)

    conn = get_connection()
    cur = conn.cursor()

    # 3. Insert episode
    episode_id = str(uuid.uuid4())
    cur.execute(
        """
        INSERT INTO episodes (id, title, xml_path, audio_path)
        VALUES (%s, %s, %s, %s)
        """,
        (episode_id, os.path.basename(xml_path), xml_path, audio_path),
    )

    # 4. Insert sections with analysis results
    for idx, section in enumerate(sections):
        sentiment, score = analyze_sentiment(section)
        topics = analyze_topics(section)
        cur.execute(
            """
            INSERT INTO podcast_sections
              (episode_id, section_idx, text, sentiment, sentiment_score, topics)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (episode_id, idx, section, sentiment, score, topics),
        )

    conn.commit()
    cur.close()
    conn.close()
    print(f"Processed {len(sections)} sections for episode {episode_id}")


if __name__ == "__main__":
    process_episode(
        xml_path="test/sample_podcast.xml",
        audio_path="test/sample_podcast.mp3",  # update if your audio path differs
    )
