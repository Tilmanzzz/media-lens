# storage/tests/test_episodes.py
import pytest
from datetime import datetime, timezone
from ..db.episodes import (
    Episode,
    EpisodeStatus,
    NewEpisode,
    get,
    save,
    update,
    get_list,
)


# --- helpers ---


def make_episode(pipeline_run_id: str, **kwargs) -> NewEpisode:
    """Builds a NewEpisode with sensible defaults, kwargs override any field."""
    defaults = dict(
        title="Test Episode",
        batch_id=pipeline_run_id,
        podcast_id="pod_1",
    )
    return NewEpisode(**{**defaults, **kwargs})


# --- get ---


class TestGet:
    def test_returns_episode_for_valid_id(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        result = get(episode_id, conn)
        assert result is not None
        assert result.id == episode_id

    def test_returns_none_for_nonexistent_id(self, conn, pipeline_run_id):
        import uuid

        result = get(str(uuid.uuid4()), conn)
        assert result is None

    def test_returns_episode_dataclass(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        result = get(episode_id, conn)
        assert isinstance(result, Episode)

    def test_returns_correct_fields(self, conn, pipeline_run_id):
        episode_id = save(
            make_episode(
                pipeline_run_id,
                title="My Podcast",
                podcast_id="pod_42",
                audio_path="bronze/ep1.mp3",
            ),
            conn,
        )
        result = get(episode_id, conn)
        assert result.title == "My Podcast"
        assert result.podcast_id == "pod_42"
        assert result.audio_path == "bronze/ep1.mp3"

    def test_defaults_status_to_pending(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        result = get(episode_id, conn)
        assert result.status == EpisodeStatus.PENDING

    def test_generated_fields_are_set(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        result = get(episode_id, conn)
        assert result.ingested_at is not None
        assert result.updated_at is not None
        assert isinstance(result.ingested_at, datetime)


# --- save ---


class TestSave:
    def test_returns_string_id(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        assert isinstance(episode_id, str)
        assert len(episode_id) == 36  # uuid format

    def test_minimal_episode_only_title(self, conn, pipeline_run_id):
        episode_id = save(NewEpisode(title="Minimal", batch_id=pipeline_run_id), conn)
        result = get(episode_id, conn)
        assert result is not None
        assert result.title == "Minimal"
        assert result.podcast_id is None
        assert result.audio_path is None

    def test_full_episode_all_fields(self, conn, pipeline_run_id):
        published = datetime(2024, 1, 1, tzinfo=timezone.utc)
        episode_id = save(
            make_episode(
                pipeline_run_id,
                audio_path="bronze/ep1.mp3",
                xml_path="bronze/ep1.xml",
                published_at=published,
            ),
            conn,
        )
        result = get(episode_id, conn)
        assert result.audio_path == "bronze/ep1.mp3"
        assert result.xml_path == "bronze/ep1.xml"
        assert result.published_at is not None

    def test_two_saves_return_different_ids(self, conn, pipeline_run_id):
        id1 = save(make_episode(pipeline_run_id), conn)
        id2 = save(make_episode(pipeline_run_id), conn)
        assert id1 != id2

    def test_requires_title(self, conn, pipeline_run_id):
        with pytest.raises(Exception):
            save(NewEpisode(title=None, batch_id=pipeline_run_id), conn)


# --- update ---


class TestUpdate:
    def test_update_single_field(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        update(episode_id, {"audio_path": "bronze/updated.mp3"}, conn)
        result = get(episode_id, conn)
        assert result.audio_path == "bronze/updated.mp3"

    def test_update_multiple_fields(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        update(
            episode_id,
            {
                "audio_path": "bronze/ep.mp3",
                "transcript_path": "silver/ep.txt",
            },
            conn,
        )
        result = get(episode_id, conn)
        assert result.audio_path == "bronze/ep.mp3"
        assert result.transcript_path == "silver/ep.txt"

    def test_update_status(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        update(episode_id, {"status": EpisodeStatus.DONE.value}, conn)
        result = get(episode_id, conn)
        assert result.status == EpisodeStatus.DONE

    def test_update_empty_dict_is_noop(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id, title="Original"), conn)
        update(episode_id, {}, conn)
        result = get(episode_id, conn)
        assert result.title == "Original"

    def test_update_invalid_field_raises(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        with pytest.raises(ValueError, match="Invalid update fields"):
            update(episode_id, {"nonexistent_field": "value"}, conn)

    def test_update_id_field_raises(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        with pytest.raises(ValueError):
            update(episode_id, {"id": "something"}, conn)


# --- get_list ---


class TestGetList:
    def test_returns_list(self, conn, pipeline_run_id):
        result = get_list(conn=conn)
        assert isinstance(result, list)

    def test_returns_saved_episodes(self, conn, pipeline_run_id):
        save(make_episode(pipeline_run_id, title="Ep A"), conn)
        save(make_episode(pipeline_run_id, title="Ep B"), conn)
        results = get_list(batch_id=pipeline_run_id, conn=conn)
        assert len(results) == 2

    def test_filter_by_podcast_id(self, conn, pipeline_run_id):
        save(make_episode(pipeline_run_id, podcast_id="pod_x"), conn)
        save(make_episode(pipeline_run_id, podcast_id="pod_y"), conn)
        results = get_list(podcast_id="pod_x", conn=conn)
        assert all(r.podcast_id == "pod_x" for r in results)

    def test_filter_by_status(self, conn, pipeline_run_id):
        episode_id = save(make_episode(pipeline_run_id), conn)
        update(episode_id, {"status": EpisodeStatus.DONE.value}, conn)
        results = get_list(
            status=EpisodeStatus.DONE, batch_id=pipeline_run_id, conn=conn
        )
        assert all(r.status == EpisodeStatus.DONE for r in results)

    def test_filter_by_batch_id(self, conn, pipeline_run_id):
        save(make_episode(pipeline_run_id), conn)
        results = get_list(batch_id=pipeline_run_id, conn=conn)
        assert all(r.batch_id == pipeline_run_id for r in results)

    def test_limit_is_respected(self, conn, pipeline_run_id):
        for i in range(5):
            save(make_episode(pipeline_run_id, title=f"Ep {i}"), conn)
        results = get_list(batch_id=pipeline_run_id, limit=3, conn=conn)
        assert len(results) <= 3

    def test_offset_paginates(self, conn, pipeline_run_id):
        for i in range(4):
            save(make_episode(pipeline_run_id, title=f"Ep {i}"), conn)
        page1 = get_list(batch_id=pipeline_run_id, limit=2, offset=0, conn=conn)
        page2 = get_list(batch_id=pipeline_run_id, limit=2, offset=2, conn=conn)
        ids1 = {r.id for r in page1}
        ids2 = {r.id for r in page2}
        assert ids1.isdisjoint(ids2)

    def test_ordered_by_ingested_at_desc(self, conn, pipeline_run_id):
        for i in range(3):
            save(make_episode(pipeline_run_id, title=f"Ep {i}"), conn)
        results = get_list(batch_id=pipeline_run_id, conn=conn)
