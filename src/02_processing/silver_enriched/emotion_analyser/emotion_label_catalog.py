from __future__ import annotations

from typing import Any, Dict, List, Union


class EmotionLabelCatalog:
    def __init__(self, id2label: Dict[Union[int, str], str]) -> None:
        normalized: Dict[int, str] = {}
        for key, value in id2label.items():
            try:
                normalized[int(key)] = str(value)
            except (TypeError, ValueError):
                continue

        self._id2label = dict(sorted(normalized.items(), key=lambda item: item[0]))

    @classmethod
    def from_model(cls, model: Any) -> "EmotionLabelCatalog":
        model_map = getattr(model.config, "id2label", {}) or {}
        return cls(model_map)

    def get_label(self, emotion_id: int) -> str:
        return self._id2label.get(emotion_id, f"UNKNOWN_{emotion_id}")

    def as_list(self) -> List[Dict[str, Union[int, str]]]:
        return [
            {"emotionID": emotion_id, "emotion": label}
            for emotion_id, label in self._id2label.items()
        ]

    def as_dict(self) -> Dict[int, str]:
        return dict(self._id2label)